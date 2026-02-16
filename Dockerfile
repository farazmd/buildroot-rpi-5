# Dockerfile
FROM ubuntu:24.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install Buildroot dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    patch \
    gzip \
    bzip2 \
    xz-utils \
    perl \
    cpio \
    unzip \
    rsync \
    file \
    bc \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    libncurses5-dev \
    libssl-dev \
    libelf-dev \
    dosfstools \
    mtools \
    fdisk \
    && rm -rf /var/lib/apt/lists/*

# Create build user
RUN useradd -m -s /bin/bash builder
USER builder
WORKDIR /home/builder

# Default command
CMD ["/bin/bash"]