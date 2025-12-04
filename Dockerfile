FROM ubuntu:jammy
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get install --no-install-recommends -y apt-transport-https
RUN apt-get update
RUN apt-get install --no-install-recommends -y curl gnupg2 ca-certificates software-properties-common nlohmann-json3-dev

RUN apt-get update && apt-get install --no-install-recommends -y git cmake build-essential sqlite3 libsqlite3-dev libssl-dev librdkafka-dev libboost-all-dev libtool libxerces-c-dev libflatbuffers-dev libjsoncpp-dev libspdlog-dev pigz libcurl4-openssl-dev uncrustify libyaml-cpp-dev libprotobuf-dev protobuf-compiler libxml2-dev libkrb5-dev uuid-dev libgsasl7-dev libgrpc++-dev libgrpc-dev pkg-config libc-ares-dev libre2-dev libabsl-dev  libopenblas-dev libomp-dev libgflags-dev && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get install --no-install-recommends -y python3.8-dev python3-pip python3.8-distutils
RUN python3.8 -m pip install stellargraph
RUN python3.8 -m pip install chardet scikit-learn joblib threadpoolctl pandas
RUN python3.8 -m pip cache purge

# Build and install OpenTelemetry C++ SDK with minimal configuration
WORKDIR /tmp
RUN git clone --branch v1.16.1 --recurse-submodules --depth 1 https://github.com/open-telemetry/opentelemetry-cpp.git && \
    cd opentelemetry-cpp && mkdir build && cd build && \
    cmake -DWITH_PROMETHEUS=ON \
          -DWITH_OTLP_GRPC=OFF \
          -DWITH_OTLP_HTTP=ON \
          -DBUILD_TESTING=OFF \
          -DWITH_EXAMPLES=OFF \
          -DWITH_BENCHMARK=OFF \
          -DWITH_LOGS_PREVIEW=OFF \
          -DWITH_ZIPKIN=OFF \
          -DWITH_JAEGER=OFF \
          -DWITH_ETW=OFF \
          -DWITH_ELASTICSEARCH=OFF \
          -DWITH_METRICS_EXEMPLAR_PREVIEW=OFF \
          -DWITH_ASYNC_EXPORT_PREVIEW=OFF \
          -DCMAKE_BUILD_TYPE=MinSizeRel \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_CXX_FLAGS="-Os" \
          .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/opentelemetry-cpp

# Strip debug symbols from OpenTelemetry libraries to reduce size
RUN find /usr/local/lib -name "libopentelemetry*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true
RUN find /usr/local/lib -name "libopentelemetry*.a" -exec strip --strip-debug {} \; 2>/dev/null || true

# Set environment variables to help CMake find OpenTelemetry
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
ENV CMAKE_PREFIX_PATH="/usr/local:$CMAKE_PREFIX_PATH"

RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get update
RUN apt-cache madison docker-ce-cli && apt-get install --no-install-recommends -y docker-ce-cli=5:24.0.* || apt-get install --no-install-recommends -y docker-ce-cli
RUN rm -rf /var/lib/apt/lists/*

WORKDIR /home/ubuntu
RUN mkdir software
WORKDIR /home/ubuntu/software

# Build METIS and clean up after installation
RUN git clone --single-branch --depth 1 --branch v5.1.1-DistDGL-v0.5 https://github.com/KarypisLab/METIS.git && \
    cd METIS && \
    git submodule update --init && \
    find . -type f -print0 | xargs -0 sed -i '/-march=native/d' && \
    make config shared=1 cc=gcc prefix=/usr/local && \
    make install && \
    cd .. && rm -rf METIS

# Build cppkafka and clean up after installation
RUN git clone --single-branch --depth 1 --branch v0.4.1 https://github.com/mfontanini/cppkafka.git && \
    mkdir cppkafka/build && cd cppkafka/build && \
    cmake .. && \
    make -j4 && \
    make install && \
    cd ../.. && rm -rf cppkafka

# Build libwebsockets and clean up after installation
RUN git clone --single-branch --depth 1 --branch v4.2-stable https://libwebsockets.org/repo/libwebsockets && \
    mkdir libwebsockets/build && cd libwebsockets/build && \
    cmake -DLWS_WITHOUT_TESTAPPS=ON -DLWS_WITHOUT_TEST_SERVER=ON -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON \
          -DLWS_WITHOUT_TEST_PING=ON -DLWS_WITHOUT_TEST_CLIENT=ON -DCMAKE_C_FLAGS="-fpic" -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make && \
    make install && \
    cd ../.. && rm -rf libwebsockets

# Build libyaml and clean up after installation
RUN git clone --single-branch --depth 1 --branch release/0.2.5 https://github.com/yaml/libyaml && \
    mkdir libyaml/build && cd libyaml/build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON .. && \
    make && \
    make install && \
    cd ../.. && rm -rf libyaml

# Build Kubernetes C client and clean up after installation
RUN git clone --single-branch --depth 1 --branch v0.11.0 https://github.com/kubernetes-client/c && \
    mkdir c/kubernetes/build && cd c/kubernetes/build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make && \
    make install && \
    cd ../../.. && rm -rf c

# Build ANTLR4 C++ runtime and clean up after installation
RUN git clone --single-branch --depth 1 --branch v4.11.1 https://github.com/antlr/antlr4.git && \
    mkdir antlr4/runtime/Cpp/build && cd antlr4/runtime/Cpp/build && \
    cmake .. && \
    make install && \
    cd ../../../.. && rm -rf antlr4

# Build libhdfs3 and clean up after installation
RUN git clone --single-branch --depth 1 https://github.com/miyurud/libhdfs3.git && \
    mkdir libhdfs3/build && cd libhdfs3/build && \
    ../bootstrap --prefix=/usr/local/libhdfs3 && \
    make -j8 && \
    make install && \
    cd ../.. && rm -rf libhdfs3

# Upgrade CMake and clean up after installation
RUN curl -L https://github.com/Kitware/CMake/releases/download/v3.29.6/cmake-3.29.6.tar.gz -o /tmp/cmake-3.29.6.tar.gz && \
    tar -zxvf /tmp/cmake-3.29.6.tar.gz -C /tmp && \
    cd /tmp/cmake-3.29.6 && \
    ./bootstrap && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/cmake-3.29.6 /tmp/cmake-3.29.6.tar.gz

# Build FAISS and clean up after installation
WORKDIR /tmp
RUN apt-get update && apt-get install --no-install-recommends -y git libopenblas-dev libomp-dev libgflags-dev && \
    git clone --depth=1 https://github.com/facebookresearch/faiss.git && \
    cd faiss && mkdir build && cd build && \
    cmake -DFAISS_ENABLE_PYTHON=OFF -DFAISS_ENABLE_GPU=OFF .. && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/faiss

# Generate ANTLR grammar files and clean up
WORKDIR /home/ubuntu/software
RUN mkdir -p code && cd code && \
    apt-get update && apt-get install --no-install-recommends -y default-jre && \
    curl -O https://s3.amazonaws.com/artifacts.opencypher.org/M23/Cypher.g4 && \
    curl -O https://www.antlr.org/download/antlr-4.13.2-complete.jar && \
    java -jar antlr-4.13.2-complete.jar -Dlanguage=Cpp -visitor Cypher.g4 && \
    mkdir -p ../antlr && \
    mv *.cpp *.h ../antlr/ && \
    cd .. && rm -rf code && \
    apt-get purge -y --autoremove default-jre

# Final cleanup: Remove git and any remaining build artifacts
RUN apt-get purge -y --autoremove git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/* && \
    rm -rf /root/.cache

# Strip all installed libraries to reduce size further
RUN find /usr/local/lib -type f -name "*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true
RUN find /usr/local/lib -type f -name "*.a" -exec strip --strip-debug {} \; 2>/dev/null || true

WORKDIR /home/ubuntu/software
