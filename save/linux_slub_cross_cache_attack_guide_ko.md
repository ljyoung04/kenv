# Linux SLUB Cross-Cache Attack 실전 이해 가이드

> 사례 출발점: CVE-2026-46242 LTS 6.12.67 익스플로잇  
> 목적: 특정 CVE의 숫자를 외우는 것이 아니라, 다른 커널 객체와 취약점에서도 cross-cache 가능성을 판단하고 필요한 값을 산출할 수 있도록 원리를 설명한다.  
> 범위: Linux의 SLUB allocator를 전제로 한다. 커널 버전·설정·아키텍처에 따라 세부 상태 전이와 tunable 의미가 달라질 수 있으므로 실제 타깃 소스와 런타임 측정이 최종 기준이다.

## 1. Cross-cache attack이 정확히 무엇인가

SLUB에서 한 캐시는 보통 동일한 종류 또는 동일한 크기의 객체를 관리한다. 예를 들어:

```text
filp cache       → struct file
kmalloc-192      → 192바이트 일반 할당
kmalloc-cg-256   → accounting되는 256바이트 일반 할당
```

UAF가 생긴 객체의 슬롯을 같은 캐시의 다른 객체로 덮는 것은 **same-cache reclaim**이다.

```text
취약 객체 A free
      ↓
같은 SLUB cache에서 객체 B allocate
      ↓
A의 옛 주소 == B의 새 주소
```

반면 cross-cache attack은 객체 슬롯이 아니라 그 객체들을 담던 **slab backing page 자체**를 캐시 밖으로 내보낸 뒤, page allocator를 통해 전혀 다른 용도의 할당으로 가져온다.

```text
victim object
  └─ victim slab
      └─ 물리 페이지
            │ 모든 객체 free
            ▼
       SLUB에서 slab 폐기
            │
            ▼
       buddy/page allocator
            │
            ▼
attacker-controlled page allocation
예: pipe data, socket page, page-sized xattr 등
```

따라서 cross-cache의 본질은:

> 객체 allocator에서 생긴 dangling pointer가 가리키는 물리 페이지의 소유권을 page allocator까지 되돌린 뒤, 사용자가 내용을 제어할 수 있는 다른 subsystem의 페이지로 소유권을 바꾸는 것

이다.

## 2. 왜 굳이 캐시 경계를 넘어가는가

same-cache reclaim만으로 충분한 경우도 많다. 예를 들어 해제된 객체와 같은 `kmalloc-N` 캐시에 함수 포인터가 있는 다른 객체를 넣을 수 있다면 cross-cache는 필요 없다.

하지만 다음 상황에서는 cross-cache가 유용하다.

1. victim이 `filp`, `task_struct`, 특정 inode cache처럼 **전용 cache**에 있다.
2. 같은 cache의 대체 객체는 사용자가 원하는 바이트를 충분히 제어할 수 없다.
3. cache merging이 비활성화됐거나 hardening 때문에 이종 객체가 같은 cache에 들어오지 않는다.
4. 같은 cache reclaim은 가능하지만, 공격에 필요한 offset에 원하는 포인터·길이·함수 포인터를 만들기 어렵다.
5. dangling pointer가 오래 유지되어 slab page를 비우고 다시 할당할 시간이 있다.

cross-cache에 성공하면 공격자가 page 내용을 대량으로 제어할 수 있어 다음과 같은 primitive로 확장하기 쉽다.

- 가짜 구조체 배치
- 함수 포인터 또는 ops table 위조
- 길이·주소 필드 위조를 통한 OOB/AAR/AAW
- 배열이나 descriptor table 위조
- payload 또는 ROP/JOP 데이터를 알려진 페이지에 배치

다만 비용도 크다.

- victim이 속한 slab의 나머지 객체를 모두 free해야 한다.
- per-CPU와 per-node SLUB 상태를 제어해야 한다.
- RCU, quarantine, memcg, NUMA, page order 같은 변수가 추가된다.
- page allocator에 반환된 뒤 원하는 page spray가 같은 물리 페이지를 받아야 한다.

## 3. allocator 계층을 먼저 이해하기

### 3.1 Page allocator와 SLUB의 관계

Linux에서 `alloc_pages()` 계열은 `2^order`개의 연속 페이지를 할당한다. 공식 커널 문서도 `alloc_pages(gfp, order)`가 `1 << order`개의 연속 페이지를 반환한다고 설명한다. 작은 동일형 객체가 많이 필요할 때는 slab cache allocator가 page allocator에서 페이지 묶음을 받아 여러 객체로 나눈다.

참고:

- [Linux Memory Allocation Guide](https://docs.kernel.org/core-api/memory-allocation.html)
- [Linux Memory Management APIs](https://docs.kernel.org/core-api/mm-api.html)

개념적으로:

```text
buddy allocator
  ├─ order-0: 1 page
  ├─ order-1: 2 contiguous pages
  ├─ order-2: 4 contiguous pages
  └─ ...
       │
       ▼
SLUB cache가 1개 이상의 page를 slab으로 받음
       │
       ├─ object 0
       ├─ object 1
       ├─ object 2
       └─ ...
```

여기서 용어를 구분해야 한다.

- **object size**: 캐시가 사용자에게 주는 객체의 stride. padding, alignment, redzone 때문에 C의 `sizeof`와 다를 수 있다.
- **slab order**: slab 하나가 사용하는 페이지 수의 지수. 페이지 수는 `2^order`.
- **objects per slab**: 한 slab에 들어가는 객체 수.
- **slab page/folio**: 객체들을 실제로 담는 backing page 묶음.
- **cache**: 동일 layout과 정책을 공유하는 slab들의 집합.

### 3.2 CPU slab, partial slab, node list

SLUB은 성능을 위해 전역 lock 없이 빠르게 할당하려고 CPU별 상태를 둔다. 단순화하면:

```text
CPU별 현재 slab
    │
    ├─ freelist에 빈 object 있음 → fast path allocate
    │
    └─ 부족하면 per-CPU partial 또는 node partial에서 slab 획득

per-CPU partial slabs
    │
    └─ 해당 CPU가 빠르게 재사용할 부분적으로 빈 slab

per-node partial list
    │
    └─ NUMA node 차원의 부분 slab

완전히 빈 slab
    │
    ├─ 정책상 partial로 잠시 보존될 수 있음
    └─ discard되면 page allocator로 반환
```

따라서 “victim slab의 모든 객체를 free했다”는 사실만으로는 부족하다. 빈 slab이 CPU 또는 node의 partial 상태에 남으면 아직 cross-cache가 아니다. backing page가 실제로 page allocator에 반환되어야 한다.

### 3.3 `SLAB_TYPESAFE_BY_RCU`의 오해

공식 문서의 핵심은 다음과 같다.

- 이 플래그는 **개별 객체의 재사용을 지연하지 않는다**.
- slab page 자체가 해제되는 시점만 RCU grace period 뒤로 미룬다.

참고: [Linux MM API의 `SLAB_TYPESAFE_BY_RCU` 설명](https://docs.kernel.org/7.1/core-api/mm-api.html)

즉:

```text
kmem_cache_free(object)
   ├─ 그 object slot은 같은 cache에서 즉시 재사용될 수 있음
   └─ slab backing page의 page allocator 반환만 RCU 뒤로 지연
```

cross-cache에서는 바로 두 번째 지연이 중요하다. free 직후 page spray를 시작하면 목표 page가 아직 SLUB 소유라 절대 잡히지 않는다.

## 4. 공격이 성립하기 위한 필수 조건

아래 항목 중 하나라도 충족하지 않으면 전략을 바꾸거나 추가 primitive가 필요하다.

### 4.1 오래 유지되는 dangling reference

victim을 free한 뒤에도 어떤 경로가 옛 주소를 사용해야 한다.

필요한 질문:

- dangling pointer를 가진 owner 객체는 얼마나 오래 사는가?
- owner를 유지한 채 victim과 주변 객체를 free할 수 있는가?
- 최종 dereference를 원하는 시점까지 미룰 수 있는가?
- 중간에 reference validation, generation check, refcount check가 있는가?
- reclaim page 내용이 바뀌었을 때 destructor가 먼저 호출되어 crash하지 않는가?

CVE-2026-46242에서는 `epitem->ffd.file`이 dangling pointer 역할을 하고, `epoll_wait()`까지 사용을 미룰 수 있다.

### 4.2 victim slab의 다른 객체를 해제할 방법

목표 slab에 단 하나의 live object라도 남으면 slab page는 반환되지 않는다.

따라서 다음 중 하나가 필요하다.

- victim slab에 들어갈 객체들을 공격자가 직접 대량 allocate/free할 수 있다.
- victim을 공격자가 만든 객체들 사이에 배치할 수 있다.
- 자연스럽게 short-lived인 같은 cache 객체들 사이에 victim을 넣을 수 있다.
- slab의 다른 live object를 식별하고 lifetime을 종료할 수 있다.

전용 cache라 하더라도 사용자 syscall로 동일 객체를 대량 생성할 수 있으면 좋은 후보가 된다. `struct file`은 `open()`, `epoll_create()`, `socket()`, `pipe()` 등으로 많이 만들 수 있다는 장점이 있다.

### 4.3 page 단위의 attacker-controlled reclaim source

SLUB에서 반환된 페이지를 다시 요청하고 그 내용을 원하는 바이트로 채울 수 있어야 한다.

좋은 reclaim source의 조건:

1. page allocator에서 직접 또는 거의 직접 페이지를 받는다.
2. allocation order가 victim slab과 호환된다.
3. GFP zone과 NUMA node가 victim page가 있던 곳과 호환된다.
4. 사용자 입력이 페이지 대부분에 복사된다.
5. 많은 페이지를 non-blocking 또는 충분한 capacity로 allocate할 수 있다.
6. 할당을 유지하면서 내용을 갱신할 수 있다.

pipe data page가 자주 쓰이는 이유는:

- 보통 order-0 page를 얻는다.
- `write()` 데이터가 page에 들어간다.
- pipe capacity 범위에서 여러 page를 안정적으로 보유한다.
- `read()`로 page를 release한 뒤 새 내용을 다시 `write()`할 수 있다.

하지만 pipe가 항상 최선은 아니다. victim slab이 higher-order이거나 특정 zone/memcg에 있으면 다른 source가 더 적합할 수 있다.

### 4.4 page 안의 victim offset을 처리할 방법

dangling pointer는 slab 시작이 아니라 특정 object slot을 가리킨다.

가능한 전략:

- 정확한 slot index를 heap grooming으로 안다.
- victim 주소를 leak해 page offset을 계산한다.
- object stride마다 같은 fake object를 반복하는 tiling을 한다.
- 여러 payload variant를 서로 다른 sprayed page에 넣는다.
- fake object가 어느 alignment에서도 최소한 안전하게 해석되도록 설계한다.

CVE-2026-46242는 `sizeof(struct file) == 192` stride로 페이지 전체를 타일링한다.

## 5. 사전에 반드시 알아야 하는 값

이 절이 실제 이식에서 가장 중요하다. 아래 표의 값을 먼저 확보해야 grooming 공식을 세울 수 있다.

| 분류 | 필요한 값 | 왜 필요한가 |
|---|---|---|
| victim | 정확한 slab cache 이름 | 어떤 allocator 상태를 조작할지 결정 |
| victim | 실제 object stride | slab 안의 배치 및 tiling 계산 |
| victim | allocation/free API와 call path | 언제 어느 CPU/node/cache에서 할당·해제되는지 판단 |
| slab | slab order | backing page 수와 reclaim source order 선택 |
| slab | objects per slab | slab 하나를 채우고 비우는 객체 수 |
| SLUB | `cpu_partial` 및 관련 정책 | 빈 slab을 CPU partial에서 밀어내는 데 필요한 양 |
| SLUB | `min_partial`/node partial 정책 | node partial에서 slab이 보존되는지 판단 |
| lifetime | RCU/free callback 종류와 지연 | page spray 시작 시점 결정 |
| topology | CPU affinity와 NUMA node | 같은 CPU cache와 같은 node를 재사용할 확률 확보 |
| allocation | GFP flags, zone, memcg charge | victim page와 reclaim page가 같은 free pool을 공유하는지 판단 |
| payload | dangling pointer의 page offset | fake object 배치 위치 |
| payload | dereference되는 필드 offset | 필요한 필드만 정확히 위조 |
| spray | reclaim allocation order와 capacity | 몇 페이지를 어떤 방법으로 뿌릴지 결정 |
| validation | known value 또는 semantic oracle | 목표 page를 실제로 잡았는지 확인 |

### 5.1 cache 이름과 실제 object size

소스에서 `sizeof(struct victim)`만 보는 것은 불충분할 수 있다.

이유:

- `kmalloc(size)`는 size class로 반올림된다.
- alignment가 stride를 늘릴 수 있다.
- redzone, KASAN, debug metadata가 layout에 영향을 줄 수 있다.
- slab merging 때문에 이름이 다른 요청이 같은 cache를 공유할 수 있다.
- `__GFP_ACCOUNT` 여부에 따라 `kmalloc-cg-*` 계열로 갈 수 있다.
- 전용 `kmem_cache_create()` cache일 수 있다.

확인 방법:

1. 타깃 커널 소스에서 allocation site를 찾는다.
2. `kmem_cache_alloc(cachep, ...)`이면 `cachep` 생성 지점을 추적한다.
3. `kmalloc(size, flags)`이면 컴파일 후 실제 size class를 확인한다.
4. 연구 VM에서 `/sys/kernel/slab/<cache>/` 또는 `slabinfo`를 확인한다.
5. tracepoint/kprobe로 실제 cache를 관측한다.

유용한 sysfs 항목은 커널에 따라 다음을 포함한다.

```text
/sys/kernel/slab/<cache>/object_size
/sys/kernel/slab/<cache>/objsize
/sys/kernel/slab/<cache>/size
/sys/kernel/slab/<cache>/order
/sys/kernel/slab/<cache>/objects
/sys/kernel/slab/<cache>/cpu_partial
/sys/kernel/slab/<cache>/partial
/sys/kernel/slab/<cache>/slabs
```

정확한 파일 존재 여부와 의미는 커널 버전·설정에 따라 확인해야 한다. SLUB debug와 cache alias 확인에는 공식 [Short users guide for SLUB](https://www.kernel.org/doc/html/v5.15/vm/slub.html)도 유용하다.

### 5.2 objects per slab

단순 근삿값은:

```text
slab_bytes = PAGE_SIZE × 2^order
objects_per_slab ≈ floor(usable_slab_bytes / object_stride)
```

하지만 실제 값은 slab metadata 배치, alignment, debug 옵션 때문에 달라질 수 있다. 따라서 sysfs의 `objects`나 `slabinfo`, 또는 해당 빌드의 `kmem_cache` 값을 기준으로 해야 한다.

CVE-2026-46242 LTS의 filp cache 값은:

```text
object stride      = 192
objects per slab   = 21
slab order         = 0
```

4096 / 192는 21이고 64바이트가 남는다. 이 타깃에서는 한 페이지에 21개가 들어간다.

### 5.3 `cpu_partial`

`cpu_partial`은 CPU가 빠른 재사용을 위해 보존하는 partial 상태의 한도를 결정한다. 중요한 주의점은 커널 세대에 따라 이것을 “slab 개수”처럼 단순 해석하면 틀릴 수 있다는 것이다. SLUB 내부는 partial slab의 free object 수를 기준으로 accounting하는 코드도 사용한다.

따라서 실전에서는:

1. 해당 타깃의 `mm/slub.c`에서 `cpu_partial` 비교와 `put_cpu_partial()` 경로를 확인한다.
2. sysfs 값을 읽는다.
3. 한 slab의 objects 수와 결합해 필요한 prefill/free 양을 실험으로 보정한다.

CVE 코드가 사용한 값은:

```text
cpu_partial          = 12
objects per slab     = 21
prefill object count = 12 × 21 = 252
```

이 수식은 해당 exploit에서 관측한 filp cache geometry에 맞춘 것이다. 다른 커널에 무조건 `cpu_partial × objects_per_slab`을 적용하는 공식은 아니다.

### 5.4 slab order

victim slab이 order-0이면 pipe의 order-0 page와 자연스럽게 맞는다.

victim slab이 order-1이라면:

```text
victim slab = 2 contiguous pages
```

이를 반환한 뒤 order-0 allocation 두 개가 쪼개서 가져갈 수도 있지만, 어느 절반을 잡는지와 split timing이 불확실해진다. 더 안정적인 방법은 같은 order와 allocation constraints를 가진 reclaim source를 찾는 것이다.

필요한 계산:

```text
slab page count = 2^order
slab bytes      = PAGE_SIZE × 2^order
victim page index within slab =
    floor((victim_addr - slab_base) / PAGE_SIZE)
```

### 5.5 GFP flags, zone, NUMA, memcg

page allocator는 모든 free page를 하나의 전역 더미로 관리하지 않는다.

영향을 주는 요소:

- `GFP_KERNEL`, `GFP_ATOMIC` 등 reclaim/수면 정책
- `GFP_DMA`, `GFP_DMA32`, `__GFP_HIGHMEM` 같은 zone modifier
- `__GFP_ACCOUNT`와 memory cgroup
- NUMA node와 현재 CPU
- cpuset/mempolicy
- movable/reclaimable 분류
- allocation order

victim slab page가 node 1에 반환됐는데 page spray가 node 0에서만 일어나면 성공률이 크게 낮아진다. 그래서 grooming, victim free, reclaim spray를 같은 CPU 또는 같은 NUMA node에서 수행하는 것이 보통 유리하다.

사전에 확인할 것:

```text
victim allocation의 gfp flags
reclaim source의 gfp flags
둘의 allowed zone
둘의 memcg accounting 여부
실행 스레드의 CPU/NUMA affinity
```

## 6. 일반화한 공격 단계

cross-cache는 크게 `prepare → isolate → drain → reclaim → validate → use` 여섯 단계로 생각하면 이식하기 쉽다.

## 6.1 Prepare: allocator 상태를 준비한다

목표:

- victim이 새롭거나 예측 가능한 slab에 들어가게 한다.
- 기존 partial slab의 빈 슬롯 때문에 victim이 예상 밖 slab에 들어가는 것을 줄인다.
- 이후 slab을 비울 수 있도록 같은 slab의 이웃 객체 대부분을 공격자가 소유한다.

일반 패턴:

```text
1. 같은 cache의 객체를 충분히 allocate해 기존 빈 슬롯을 소비
2. 새 slab이 생길 경계까지 채움
3. victim allocate
4. 같은 cache 객체를 더 allocate해 victim slab의 남은 슬롯을 채움
```

이를 “victim을 attacker-controlled objects로 둘러싼다”고 표현한다.

개념적 수식:

```text
N = objects_per_slab

pre-fill count  = 기존 partial 상태를 소진할 만큼
before count    = victim이 새 slab의 원하는 index에 오도록 하는 수
after count     = N - before_count - 1
```

하지만 freelist randomization 때문에 “N번째 allocation은 slot N” 같은 물리 순서를 기대하면 안 된다. 여기서 중요한 것은 정확한 주소 순서보다 victim slab의 나머지 live object를 공격자가 소유하는 것이다.

### CVE-2026-46242의 prepare

```text
252개의 /dev/null file → CPU partial 상태를 채우는 용도
victim 전후 총 42개 file → 두 slab 범위에서 victim을 감싸는 용도
```

두 slab을 쓰는 이유는 slab 경계를 정확히 모를 때도 victim slab의 앞뒤 슬롯을 공격자 객체로 덮을 확률을 높이기 위해서다.

## 6.2 Isolate: dangling pointer를 만든다

여기에는 원래 취약점이 필요하다.

```text
owner ──pointer──► victim
                    │
                    └─ free

owner ──dangling──► freed victim slot
```

cross-cache 자체는 UAF를 만드는 취약점이 아니다. 이미 존재하는 dangling pointer를 더 강한 메모리 primitive로 바꾸는 heap exploitation 기법이다.

이 단계에서 반드시 검사할 것:

- victim free가 실제 마지막 reference를 제거하는가?
- RCU callback 등으로 실제 free가 비동기인가?
- dangling owner를 닫거나 free하면 victim을 건드리는 destructor가 실행되는가?
- heap grooming 객체를 free하는 동안 dangling path가 우연히 실행되지 않는가?

## 6.3 Drain: victim slab을 완전히 비워 SLUB 밖으로 보낸다

기본 작업:

```text
1. victim free
2. victim slab의 attacker-owned 이웃 objects 모두 free
3. 필요하다면 CPU partial을 넘치게 하거나 flush
4. node partial 보존 조건을 넘김
5. RCU/quarantine 지연이 끝날 때까지 기다림
```

여기서 가장 흔한 실패는 2번만 하고 바로 spray하는 것이다.

### 왜 추가 slab/객체를 free하는가

SLUB은 빈 slab을 즉시 page allocator에 주지 않고 partial로 보유할 수 있다. 목표 slab보다 먼저 partial 목록에 있던 slab을 밀어내거나 threshold를 넘게 하려면 여러 slab의 상태를 함께 바꿔야 할 수 있다.

일반적인 연구 절차:

1. `objects_per_slab` 단위로 객체 그룹을 만든다.
2. 그룹마다 일부 또는 전부를 free해 partial slab을 만든다.
3. 목표 CPU의 partial 한도를 채운다.
4. 목표 slab을 empty로 만든다.
5. 추가 free로 목표 slab이 node list 또는 discard 경로로 이동하게 한다.

정확한 free 순서는 해당 `mm/slub.c`의:

```text
slab_free()
do_slab_free()
__slab_free()
deactivate_slab()
put_cpu_partial()
unfreeze_partials()
discard_slab()
```

관련 경로를 타깃 버전에서 읽고 정해야 한다. 함수 이름은 버전에 따라 달라질 수 있다.

### RCU와 quarantine

가능한 지연 원인:

- `SLAB_TYPESAFE_BY_RCU`: slab page 반환을 grace period 뒤로 미룸
- 객체별 `call_rcu()`: 각 객체 free callback이 끝나야 slab이 빔
- KASAN quarantine: freed object/page 재사용을 늦춤
- `CONFIG_SLUB_DEBUG`: metadata 및 free 동작 변화
- reference count의 비동기 감소
- workqueue/task_work에서 실제 release

고정 `usleep()`은 PoC에서는 편하지만 이식성이 낮다. 더 좋은 연구 방식은 tracepoint, kprobe, slab counters로 실제 `discard_slab`/page free 시점을 측정한 뒤 margin을 잡는 것이다.

## 6.4 Reclaim: page allocator에서 목표 page를 다시 가져온다

목표 page가 반환된 뒤 attacker-controlled page allocation을 여러 번 수행한다.

```text
for i in 0 .. spray_pages-1:
    allocate one compatible page
    fill with marker or fake-object template
    keep allocation alive
```

spray 개수는 다음 균형으로 정한다.

- 너무 적으면 목표 page를 못 잡는다.
- 너무 많으면 메모리 제한, pipe limit, noise, reclaim pressure가 커진다.
- allocation 사이에 지연을 두면 비동기 RCU free와 겹쳐 성공률이 오를 수 있다.
- 반대로 page가 이미 반환된 타깃에서는 한 번에 빠르게 할당해야 다른 커널 작업보다 먼저 잡을 수 있다.

### burst spray와 spread spray

**Burst**

```text
wait until expected free
→ 매우 빠르게 많은 page allocate
```

적합한 경우:

- page free 시점이 비교적 일정
- 단일 RCU slab callback 뒤에 바로 반환
- background allocator noise가 커서 선점이 중요

**Spread**

```text
짧은 간격으로 page를 하나씩 allocate
→ 긴 시간 구간을 덮음
```

적합한 경우:

- 객체별 RCU callback이 여러 개
- page free 시점 분산이 큼
- callback batch 처리 변동이 큼

CVE 소스도 LTS에는 약 10ms 기다린 뒤 burst, COS에는 약 1초 동안 분산 allocation을 사용한다. 같은 취약점이라도 free implementation 차이 때문에 reclaim schedule이 바뀐 사례다.

## 6.5 Validate: 목표 물리 페이지를 잡았는지 확인한다

spray 성공 여부를 모르고 fake ops를 호출하면 panic 가능성이 높다. 따라서 가능한 한 먼저 무해한 read 또는 semantic check를 한다.

좋은 validation의 특징:

- 올바른 page를 잡았을 때만 예측 가능한 값이 나온다.
- 실패 시 crash하지 않는다.
- 잘못된 pointer를 따라가는 범위가 작다.
- 여러 조건을 동시에 검증한다.
- 반복 실행할 수 있다.

validation 종류:

1. **Known kernel value**
   - `init_task.comm == "swapper"` 같은 안정된 값 읽기
2. **Marker readback**
   - dangling path가 spray marker를 반환하는지 확인
3. **System call return oracle**
   - 내부 상태에 따라 `0`, `-EINVAL`, `-ELOOP` 등이 달라짐
4. **Controlled benign callback**
   - 부작용이 적은 함수로 간접 호출 여부 확인
5. **Address-class check**
   - leak된 값이 canonical kernel pointer 범위와 alignment를 만족하는지 확인

false positive를 줄이려면:

```text
magic 값 1개
+ 두 번째 독립 필드
+ 구조체 포인터 alignment
+ 알려진 문자열/상수
```

를 함께 검사하는 편이 좋다.

## 6.6 Use: 겹친 페이지를 실제 primitive로 바꾼다

페이지를 잡은 뒤에는 dangling dereference 경로에 맞춰 fake object를 설계한다.

먼저 코드에서 다음을 정확히 적는다.

```text
base = dangling pointer가 가리키는 fake object 시작점

read/write/call 경로:
base + field_A_offset
      ↓ pointer dereference
ptr + field_B_offset
      ↓ indirect call 또는 copy
```

예:

```text
file
  ├─ f_inode ─► inode
  │               └─ i_ino → fdinfo에 출력
  └─ f_op ───► file_operations
                  └─ poll → 간접 호출
```

같은 dangling 객체라도 먼저 `f_inode`로 read primitive를 만들고, 필요한 주소를 구한 뒤 `f_op`로 control-flow primitive를 만드는 단계적 접근이 안전하다.

## 7. 필요한 수량을 계산하는 방법

완전히 일반적인 단일 공식은 없다. 하지만 아래 변수를 정하면 초기 grooming 설계를 만들 수 있다.

```text
P = PAGE_SIZE
O = slab order
S = slab bytes = P × 2^O
Z = object stride
N = objects per slab
C = cpu_partial 관련 한도
E = victim을 감쌀 slab 수
R = reclaim spray page 수
```

초기 근삿값:

```text
N = 타깃 sysfs/SLUB metadata의 objects 값

partial grooming objects ≈ C × N
victim enclosing objects ≈ E × N

reclaim bytes =
    R × PAGE_SIZE                  (order-0 source)
또는
    R × PAGE_SIZE × 2^source_order
```

권장 시작점:

```text
E = 2 또는 3 slabs
R = 사용 가능한 resource limit 내 수십~수백 pages
```

이후 실험으로 조정한다.

- victim slab이 잘 isolate되지 않으면 `E` 증가
- slab이 page allocator로 안 내려가면 partial grooming 양과 free 순서 변경
- page는 내려가지만 reclaim miss면 `R`, CPU/NUMA affinity, timing 변경
- wrong slot이면 tiling 또는 address leak 추가

### CVE-2026-46242 수치 대입

```text
P = 4096
O = 0
S = 4096
Z = 192
N = 21
C = 12
E = 2
R = 256

partial grooming objects = 12 × 21 = 252
enclosing objects        = 2 × 21  = 42
reclaim bytes            = 256 × 4096 = 1 MiB
```

이 값의 의미:

- 252: per-CPU partial 상태를 원하는 방향으로 포화시키기 위한 filp 객체 수
- 42: victim이 속할 가능성이 있는 두 slab의 이웃을 소유하기 위한 수
- 256 pages: page allocator에서 목표 order-0 page를 되찾을 확률을 높이는 spray 폭

## 8. Tiling 계산

victim object의 page offset을 모른다고 가정한다.

```text
page size     = P
object stride = Z
possible starts = 0, Z, 2Z, ..., kZ
단, kZ + Z <= P
```

각 시작점에 같은 fake object를 쓴다.

```pseudo
page = zero_page()
for off = 0; off + Z <= P; off += Z:
    write fake fields at page + off
```

주의할 점:

1. 실제 slab object 시작점이 page offset 0에서 시작하는지 확인한다.
2. higher-order slab이면 전체 slab의 첫 page가 아닌 다른 page에 victim이 있을 수 있다.
3. SLUB metadata가 slab 내부에 존재하는 configuration이면 usable 시작 offset이 달라질 수 있다.
4. object alignment가 `sizeof(struct)`보다 클 수 있다.
5. fake object의 포인터 필드가 다음 tile과 겹치지 않는지 확인한다.
6. kernel이 fake object의 예상 밖 필드를 읽어도 즉시 crash하지 않도록 기본값을 설계한다.

192-byte stride에서는 한 4KB page에 21개 tile을 놓을 수 있다.

```text
21 × 192 = 4032
4096 - 4032 = 64 bytes remainder
```

## 9. Reclaim source를 고르는 체크리스트

새 타깃에서 pipe를 자동 선택하지 말고 다음 표로 후보를 평가한다.

| 질문 | 좋은 답 |
|---|---|
| allocation 단위는? | victim slab order와 동일하거나 호환 |
| 어떤 GFP flags인가? | victim slab page와 같은 zone/node를 사용할 수 있음 |
| memcg accounting은? | victim과 같은 pool/charge 경로 |
| 사용자 데이터 제어량은? | 페이지 대부분 또는 필요한 offset |
| 대량 allocation 가능한가? | resource limit 안에서 수십~수백 개 |
| allocation 유지 가능한가? | trigger 전까지 page가 free되지 않음 |
| 내용 갱신 가능한가? | validation payload에서 final payload로 전환 가능 |
| cleanup은 안전한가? | miss 시 page를 release하고 재시도 가능 |
| 내부 header가 있는가? | fake object 위치와 충돌하지 않음 |

pipe source를 사용할 때 확인할 값:

```text
/proc/sys/fs/pipe-max-size
F_SETPIPE_SZ 결과
F_GETPIPE_SZ 결과
프로세스/사용자별 pipe page limit
write가 block되지 않는 실제 capacity
```

capacity를 늘리지 않고 기본 16페이지 pipe에 256페이지를 쓰면 reader가 없을 때 block되어 exploit이 멈출 수 있다. CVE 코드는 `F_SETPIPE_SZ`와 `F_GETPIPE_SZ`를 모두 검사한다.

## 10. 성공률을 좌우하는 숨은 변수

### 10.1 CPU affinity

같은 cache라도 CPU별 freelist와 partial이 다르다.

권장 실험:

```text
groom allocation CPU = X
victim allocation CPU = X
victim free CPU = X
page reclaim CPU = X
```

레이스 때문에 별도 CPU가 필요하다면, 어느 CPU가 최종 `kmem_cache_free()`를 실행하는지 커널 call path 기준으로 확인한다. syscall을 호출한 CPU와 실제 RCU callback CPU가 같다는 보장은 없다.

### 10.2 NUMA

다중 node 시스템에서는 CPU affinity가 node 선택에 영향을 준다. `/proc/<pid>/numa_maps`, sysfs topology, `numactl` 또는 커널 trace로 실제 node를 확인한다.

### 10.3 Background allocation noise

목표 page가 buddy에 반환된 직후 다른 kernel worker가 가져갈 수 있다.

대응:

- 격리된 CPU 사용
- 가능한 한 victim free와 reclaim spray 사이를 짧게 함
- RCU free 시점 예측 개선
- spray 폭 증가
- 성공 oracle과 retry loop 사용

### 10.4 Freelist randomization과 hardening

`CONFIG_SLAB_FREELIST_RANDOM`, `CONFIG_SLAB_FREELIST_HARDENED`는 object slot 재사용 예측을 어렵게 한다. 하지만 cross-cache는 최종적으로 page 소유권을 바꾸므로 freelist pointer encoding 자체를 깨야 하는 공격은 아니다.

그럼에도 victim slab을 attacker-owned 객체로 isolate하는 과정에는 allocation 순서 변동이 영향을 준다. 정확한 slot 하나를 예측하기보다:

- 여러 slab으로 감싸기
- tiling
- oracle과 retry

를 사용하는 이유다.

### 10.5 KASAN과 SLUB debug

디버그 커널은:

- object size/stride 변경
- redzone/poison 삽입
- quarantine으로 재사용 지연
- UAF 접근 즉시 report
- 다른 slab order 선택

을 만들 수 있다. KASAN reproducer에서 얻은 geometry를 production-like kernel에 그대로 적용하거나 그 반대로 적용하면 안 된다.

## 11. 관측과 디버깅 방법

cross-cache를 감으로 조정하기보다 각 경계를 따로 증명해야 한다.

### 11.1 1차: cache geometry 확인

연구 VM에서:

```text
cache 이름
object_size/size
objects per slab
order
cpu_partial
partial slab 수
총 slab 수
```

를 기록한다.

`slabinfo`를 쓸 수 있다면 allocation 전후 snapshot을 비교한다. cache merging 여부도 확인한다.

### 11.2 2차: allocation/free call path 확인

다음 질문에 답할 수 있어야 한다.

```text
victim은 어디서 allocate되는가?
마지막 ref는 어디서 감소하는가?
실제 kmem_cache_free는 즉시인가, callback인가?
어느 CPU에서 실행되는가?
slab discard 시점은 언제인가?
page allocator free 시점은 언제인가?
reclaim source는 어느 order/GFP/node에서 alloc하는가?
```

ftrace, function graph tracer, tracepoint, kprobe/bpftrace 또는 GDB를 연구 환경에서 사용할 수 있다.

### 11.3 3차: marker로 page overlap 검증

최종 fake pointer나 ROP 대신 먼저 반복 marker를 쓴다.

```text
0x4141414141414141
0x4242424242424242
page index별 서로 다른 magic
```

dangling read path가 어느 marker를 보는지 확인하면:

- 몇 번째 spray page가 목표 page인지
- victim object의 page offset
- page가 실제로 겹쳤는지

를 알 수 있다.

쓰기나 함수 호출밖에 없는 primitive라면 crash 대신 부작용이 작은 필드 또는 검증 가능한 오류 코드를 먼저 찾는 편이 안전하다.

### 11.4 단계별 성공률을 따로 측정

전체 exploit 성공률 하나만 보면 병목을 찾기 어렵다.

다음 카운터를 따로 둔다.

```text
UAF/race attempts
UAF oracle success
slab drain attempts
page reclaim validation success
fake-object primitive success
final trigger success
```

예:

```text
race 성공률 1/100
cross-cache 성공률 1/5
final primitive 성공률 4/5

전체 기대 성공률 ≈ 1/125
```

이렇게 보면 race timing을 조정할지 reclaim page 수를 늘릴지 판단할 수 있다.

## 12. 다른 취약점에 이식하는 절차

다음 순서로 조사하면 된다.

### Step 1. dangling type과 사용 지점 명세

한 장에 적는다.

```text
victim type:
allocation site:
free site:
dangling owner:
later dereference site:
읽는 필드:
쓰는 필드:
호출하는 함수 포인터:
```

### Step 2. victim cache 식별

```text
전용 cache인가?
kmalloc size class인가?
memcg cache인가?
cache merging되는가?
```

### Step 3. geometry 수집

```text
object stride Z
slab order O
objects per slab N
cpu_partial C
node partial 정책
RCU/debug flags
```

### Step 4. 같은 cache의 controllable allocator 찾기

victim 외에 같은 cache 객체를 syscall로 대량 생성·해제할 방법을 찾는다. 이것은 final reclaim object가 아니라 **slab을 채우고 비우기 위한 grooming object**다.

### Step 5. victim slab isolation 실험

처음부터 최종 exploit을 만들지 말고:

```text
groom objects allocate
victim allocate
more groom objects allocate
victim + neighbours free
slab counter 변화 확인
```

로 backing slab이 discard되는 수량과 순서를 구한다.

### Step 6. reclaim source compatibility 검토

```text
order
zone/GFP
NUMA
memcg
content control
capacity
lifetime
```

를 victim slab과 비교한다.

### Step 7. marker-only overlap PoC

가짜 함수 포인터 없이 marker가 dangling read에 보이는 것만 증명한다.

### Step 8. constrained primitive 설계

먼저 안전한 AAR, length corruption, info leak 등을 만든다. 필요한 커널 주소와 page offset을 구한다.

### Step 9. final payload 설계

주소 정보가 확보된 뒤 fake ops, fake descriptor, ROP/JOP 등 최종 primitive로 전환한다.

### Step 10. oracle과 retry 추가

각 확률적 단계에:

```text
timeout
known-value validation
clean retry
resource cleanup
panic 방지
통계 logging
```

을 넣는다.

## 13. 실패 유형별 진단표

| 증상 | 가능성 높은 원인 | 확인/대응 |
|---|---|---|
| 같은 cache 객체는 재사용되지만 page spray와 안 겹침 | slab이 partial에 남음 | partial counter, `discard_slab` 경로 확인 |
| 충분히 기다려도 overlap 없음 | slab에 live object가 남음 | enclosing object ownership 확대 |
| 간헐적으로만 overlap | RCU free 시점 변동 | burst/spread 비교, callback trace |
| single CPU에서는 되고 multi CPU에서 불안정 | per-CPU cache 분산 | affinity 고정, 실제 free CPU 추적 |
| NUMA 시스템에서 급격히 실패 | 다른 node에서 spray | membind/CPU node 정렬 |
| marker는 보이나 fake object가 crash | wrong slot/stride/필드 offset | 실제 cache `size`, page offset, tiling 검증 |
| 첫 leak은 되지만 반복 AAR 불안정 | page 내용 갱신 중 object가 dereference | double buffering, synchronization |
| pipe write가 멈춤 | capacity 부족 | `F_SETPIPE_SZ`, `F_GETPIPE_SZ`, drain 계획 |
| KASAN에서 geometry가 다름 | redzone/quarantine/debug | 실제 target build에서 재측정 |
| page reclaim 후 즉시 다른 값으로 변함 | 다른 subsystem이 같은 page를 가져감 | spray timing 단축, allocation 유지 |
| reclaim page는 잡지만 victim pointer가 다른 page를 가리킴 | higher-order slab/잘못된 page index | slab order와 victim offset 계산 |

## 14. CVE-2026-46242에 이 원리를 다시 대입

### 14.1 주어진 primitive

```text
dangling owner  = ep_uaf_waiter의 epitem
victim          = ep_uaf_target의 struct file
dangling field  = epitem->ffd.file
later use       = fdinfo read 또는 epoll_wait
victim cache    = filp
```

### 14.2 geometry

```text
FILE_SIZE               = 192
SLAB_OBJ_PER_SLAB       = 21
SLAB_CPU_PARTIAL        = 12
SLAB_NUM_POP_CPU_OBJS   = 12 × 21 = 252
SLAB_NUM_ENCLOSING_OBJS = 2 × 21 = 42
slab order              = 0
```

### 14.3 drain

1. `ep_uaf_target`을 닫아 victim `struct file`을 free한다.
2. 같은 두 slab 범위에 배치한 `/dev/null` file들을 닫는다.
3. CPU partial을 준비한 객체들을 slab 단위 간격으로 free해 목표 slab 배출을 유도한다.
4. `SLAB_TYPESAFE_BY_RCU`인 filp slab이 `rcu_free_slab`을 거쳐 반환되도록 약 10ms 기다린다.

### 14.4 reclaim

1. pipe capacity를 256페이지로 늘린다.
2. zero page를 256번 써서 order-0 page 256개를 allocation한다.
3. 목표 filp slab page가 pipe data page 중 하나로 재사용되기를 기대한다.

### 14.5 validation

모든 pipe page를 fake `struct file` tile로 채운다.

```text
fake_file.f_inode =
    &init_task.comm - offsetof(inode, i_ino)
```

`/proc/self/fdinfo/<ep_uaf_waiter>`를 읽었을 때 `ino:` 경로로 `"swapper"`가 나오면 성공이다.

### 14.6 use

같은 overlap page를:

1. `f_inode` 위조를 통한 AAR
2. `f_op` 위조를 통한 `poll` 함수 포인터 탈취

두 용도로 순차 재사용한다.

## 15. 일반화할 때 기억해야 할 핵심

cross-cache를 “많이 allocate하고 free한 뒤 pipe spray”라고 이해하면 이식에 실패하기 쉽다. 실제로는 다음 네 가지 경계를 각각 통과시키는 기술이다.

```text
[1] victim lifetime boundary
    valid object → dangling reference

[2] slab occupancy boundary
    one free object → completely empty slab

[3] allocator ownership boundary
    SLUB cache → buddy/page allocator

[4] subsystem ownership boundary
    freed slab page → attacker-controlled page allocation
```

각 경계마다 필요한 증거가 다르다.

| 경계 | 증거 |
|---|---|
| victim lifetime | UAF oracle, refcount/free trace |
| slab occupancy | 모든 이웃 객체 소유, slab counters |
| allocator ownership | `discard_slab`/page free 관측, RCU 종료 |
| subsystem ownership | marker 또는 known-value readback |

그리고 다른 취약점에 적용할 때 가장 먼저 확보해야 할 최소 데이터 세트는 다음과 같다.

```text
victim cache
object stride
slab order
objects per slab
cpu/node partial 정책
실제 free/RCU 시점
CPU와 NUMA node
victim과 reclaim source의 GFP/memcg 호환성
dangling pointer의 page offset 또는 tiling 가능성
안전한 성공 oracle
```

이 값들이 없으면 객체 수와 sleep 시간을 아무리 조정해도 재현성이 나오기 어렵다. 반대로 이 값들을 확보하고 각 allocator 경계를 독립적으로 검증하면, 특정 CVE의 magic number에 의존하지 않고 다른 UAF에도 같은 사고방식을 적용할 수 있다.

## 16. 참고 자료

- 분석 출발점: [CVE-2026-46242 `exploit.cpp`](https://github.com/J-jaeyoung/security-research/blob/submit-cve-2026-46242/pocs/linux/kernelctf/CVE-2026-46242_lts_cos/exploit/lts-6.12.67/exploit.cpp)
- Linux 공식 문서: [Memory Allocation Guide](https://docs.kernel.org/core-api/memory-allocation.html)
- Linux 공식 문서: [Memory Management APIs](https://docs.kernel.org/core-api/mm-api.html)
- Linux 공식 문서: [`SLAB_TYPESAFE_BY_RCU` 설명](https://docs.kernel.org/7.1/core-api/mm-api.html)
- Linux 공식 문서: [Short users guide for SLUB](https://www.kernel.org/doc/html/v5.15/vm/slub.html)

실제 타깃에 적용할 때는 문서보다 해당 커널 tag의 `mm/slub.c`, victim cache 생성 코드, victim allocation/free call path, reclaim source의 page allocation path를 우선해야 한다.
