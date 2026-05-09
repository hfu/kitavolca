FROM debian:bookworm

# Install system dependencies including GDAL
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    unzip \
    ca-certificates \
    jq \
    gdal-bin \
    libgdal-dev \
    python3-gdal \
    && rm -rf /var/lib/apt/lists/*

# Install tippecanoe from source (Felt maintained)
RUN cd /tmp && \
    git clone https://github.com/felt/tippecanoe.git && \
    cd tippecanoe && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/tippecanoe

# Install go-pmtiles binary (optional; tippecanoe can output directly)
# RUN mkdir -p /tmp/pmtiles && \
#     cd /tmp/pmtiles && \
#     curl -sL https://github.com/protomaps/PMTiles/releases/download/v4.18.3/pmtiles_linux_x86_64 -o pmtiles && \
#     chmod +x pmtiles && \
#     mv pmtiles /usr/local/bin/ && \
#     cd / && \
#     rm -rf /tmp/pmtiles

# Verify installations
RUN ogrinfo --version && \
    tippecanoe --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
