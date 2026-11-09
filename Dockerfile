FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Basic build tools
RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses-dev \
    dwarves \
    cpio \
    wget \
    xz-utils \
    git \
    python3 \
    python3-pip \
    bear \
    # debootstrap & image creation
    debootstrap \
    qemu-user-static \
    qemu-system-x86 \
    e2fsprogs \
    sudo \
    openssh-client \
    # LLVM/Clang 19
    lsb-release \
    software-properties-common \
    gnupg \
    gosu \
    # GDB build dependencies & GEF
    python3-dev \
    python3-venv \
    texinfo \
    libexpat1-dev \
    liblzma-dev \
    libdebuginfod-dev \
    libbabeltrace-dev \
    libsource-highlight-dev \
    guile-3.0-dev \
    libgmp-dev \
    libmpfr-dev \
    # utilities
    nano \
    curl \
    socat \
    fzf \
    lsof \
    ripgrep \
    fd-find \
    bat \
    eza \
    tree \
    htop \
    tmux \
    jq \
    strace \
    ltrace \
    man-db \
    less \
    zip \
    unzip \
    inotify-tools \
    net-tools \
    openssh-server \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Locale setup
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    sed -i 's/# ko_KR.UTF-8/ko_KR.UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install LLVM-19
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/noble/ llvm-toolchain-noble-19 main" \
      > /etc/apt/sources.list.d/llvm-19.list && \
    apt-get update && apt-get install -y \
    clang-19 \
    lld-19 \
    llvm-19 \
    && rm -rf /var/lib/apt/lists/*

# Build patched GDB (fzf Ctrl+R history search)
COPY dotfiles/0001-gdb-ctrl-r-fzf-fuzzy-history-search.patch /tmp/gdb-fzf.patch
RUN git clone --depth=1 --branch gdb-17.1-release git://sourceware.org/git/binutils-gdb.git /tmp/binutils-gdb && \
    cd /tmp/binutils-gdb && \
    git apply /tmp/gdb-fzf.patch && \
    mkdir build && cd build && \
    ../configure \
      --prefix=/usr/local \
      --with-python=python3 \
      --with-expat \
      --with-lzma \
      --with-debuginfod \
      --with-babeltrace \
      --enable-source-highlight \
      --enable-tui \
      --with-guile \
      --enable-targets=all \
      --with-separate-debug-dir=/usr/lib/debug && \
    make -j$(nproc) all-gdb && \
    make install-gdb && \
    rm -rf /tmp/binutils-gdb /tmp/gdb-fzf.patch

# Install dotfiles (oh-my-bash, GEF, smart-bash-history, zoxide) into /etc/skel
COPY dotfiles/ /tmp/dotfiles/
RUN chmod +x /tmp/dotfiles/install.sh && /tmp/dotfiles/install.sh && rm -rf /tmp/dotfiles

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

# kernelctf setting
RUN git clone --depth=1 https://github.com/google/security-research.git /workspace/share/kctf/security-research

RUN git clone --depth=1 https://github.com/google/kernel-research.git /workspace/share/kctf/kernel-research

# Default interactive shell
SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["entrypoint.sh"]
CMD ["/bin/bash"]
