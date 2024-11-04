# Use Ubuntu 24.04 as the base image
FROM ubuntu:24.04

# Ensure /etc/passwd and /etc/group contain entries for root
RUN echo "root:x:0:0:root:/root:/bin/bash" > /etc/passwd && \
    echo "root:x:0:" > /etc/group

# Set ARGs for versions
ARG version=1.16.1
ARG opensslversion=3.2.1
ARG zlibversion=1.3.1

# Install required packages and build dependencies
RUN apt-get update && \
    apt-get install -y \
    unzip bash gcc make pcre build-base pcre-dev perl-dev linux-headers \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Nginx, OpenSSL, zlib, and the Nginx modules
RUN wget https://nginx.org/download/nginx-${version}.tar.gz && \
    tar -xf nginx-${version}.tar.gz && \
    wget https://github.com/yaoweibin/ngx_http_substitutions_filter_module/archive/master.zip -O subs.zip && \
    unzip subs.zip && \
    wget https://github.com/openresty/headers-more-nginx-module/archive/master.zip -O headers.zip && \
    unzip headers.zip && \
    wget https://www.openssl.org/source/openssl-${opensslversion}.tar.gz && \
    tar -xf openssl-${opensslversion}.tar.gz && \
    wget https://www.zlib.net/zlib-${zlibversion}.tar.gz && \
    tar -xf zlib-${zlibversion}.tar.gz

# Set the working directory to the Nginx source
WORKDIR /nginx-${version}

# Configure Nginx with desired modules and settings
RUN ./configure \
    --prefix=/usr/share/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/lock/nginx.lock \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --user=www-data \
    --group=www-data \
    --with-compat \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-http_realip_module \
    --with-http_v2_module \
    --with-stream_ssl_preread_module \
    --with-stream_ssl_module \
    --with-http_auth_request_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-openssl=../openssl-${opensslversion} \
    --with-zlib=../zlib-${zlibversion} \
    --add-module=/ngx_http_substitutions_filter_module-master \
    --add-module=/headers-more-nginx-module-master

# Compile and install Nginx
RUN make && make install

# Create necessary directories and add placeholders for runtime use
RUN mkdir -p /var/www /usr/share/.empty /var/run/.empty /var/lock/.empty

# Copy configuration files, certificates, and custom templates
COPY etc /etc
COPY www /var/www
COPY ConfigTemplate /etc/nginx
COPY ConfigCustom /etc/nginx
COPY Certs/CA /etc/ssl/certs
COPY Certs/Server /etc/ssl/certs

# Expose port 80 for HTTP
EXPOSE 80

# Set the entrypoint for Nginx to run in the foreground
ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]
