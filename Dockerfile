FROM ubuntu:22.10

# for the VNC connection
EXPOSE 5900
# for the browser VNC client
EXPOSE 5901
# Use environment variable to allow custom VNC passwords
ENV VNC_PASSWD=123456

# Make sure the dependencies are met
ENV APT_INSTALL_PRE="apt -o Acquire::ForceIPv4=true update && DEBIAN_FRONTEND=noninteractive apt -o Acquire::ForceIPv4=true install -y --no-install-recommends"
ENV APT_INSTALL_POST="&& apt clean -y && rm -rf /var/lib/apt/lists/*"
# Make sure the dependencies are met
RUN eval ${APT_INSTALL_PRE} tigervnc-standalone-server tigervnc-common tigervnc-tools fluxbox eterm xterm git net-tools python-is-python3 python3 python3-numpy ca-certificates scrot ${APT_INSTALL_POST}

# Install VNC. Requires net-tools, python and python-numpy
RUN git clone --branch v1.2.0 --single-branch https://github.com/novnc/noVNC.git /opt/noVNC
RUN git clone --branch v0.9.0 --single-branch https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify
RUN ln -s /opt/noVNC/vnc.html /opt/noVNC/index.html

# Add menu entries to the container
RUN echo "?package(bash):needs=\"X11\" section=\"DockerCustom\" title=\"Xterm\" command=\"xterm -ls -bg black -fg white\"" >> /usr/share/menu/custom-docker && update-menus

# Set timezone to UTC
RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone

# Add in a health status
HEALTHCHECK --start-period=10s CMD bash -c "if [ \"`pidof -x Xtigervnc | wc -l`\" == "1" ]; then exit 0; else exit 1; fi"

# Add in non-root user
ENV UID_OF_DOCKERUSER 1000
RUN useradd -m -s /bin/bash -g users -u ${UID_OF_DOCKERUSER} dockerUser
RUN chown -R dockerUser:users /home/dockerUser && chown dockerUser:users /opt

RUN export DEBIAN_FRONTEND=noninteractive && apt update -y && apt install -y xfce4 xfce4-goodies

USER dockerUser

# Copy various files to their respective places
COPY --chown=dockerUser:users container_startup.sh /opt/container_startup.sh
COPY --chown=dockerUser:users x11vnc_entrypoint.sh /opt/x11vnc_entrypoint.sh
# Subsequent images can put their scripts to run at startup here
RUN mkdir /opt/startup_scripts

ENTRYPOINT ["bash", "/opt/container_startup.sh"]

# OBS Setup
########################

USER root

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -y \
    && apt-get install -y git sudo software-properties-common checkinstall wget avahi-daemon \
    && apt-get update -y \
    && apt-get upgrade -y \
    && apt clean all -y 

# compile cmake
RUN apt install -y build-essential libssl-dev && \
    wget https://github.com/Kitware/CMake/releases/download/v3.20.2/cmake-3.20.2.tar.gz && \
    tar -zxvf cmake-3.20.2.tar.gz && \
    cd cmake-3.20.2 && \
    ./bootstrap && \
    make  && \
    make install 

# https://gist.github.com/Kusmeroglu/ef81c4f96369f890fcdc0616652430ad

# compile srt
RUN mkdir ~/ffmpeg_sources \
    && cd ~/ffmpeg_sources \
    && git clone --depth 1 https://github.com/Haivision/srt.git \
    && mkdir srt/build \
    && cd ~/ffmpeg_sources/srt/build \
    && cmake -DENABLE_C_DEPS=ON -DENABLE_SHARED=ON -DENABLE_STATIC=OFF .. \
    && make \
    && make install

# install ffmpeg dependencies
RUN apt-get update -qq && apt-get -y install \
  autoconf \
  automake \
  build-essential \
  git-core \
  libass-dev \
  libfreetype6-dev \
  libgnutls28-dev \
  libsdl2-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  pkg-config \
  texinfo \
  wget \
  curl \
  yasm \
  zlib1g-dev \
  libx264-dev \
  libx265-dev \
  libnuma-dev \
  libfdk-aac-dev \
  libmp3lame-dev

# compile ffmpeg
RUN cd ~/ffmpeg_sources && \
    wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
    tar xjvf ffmpeg-snapshot.tar.bz2
RUN cd ~/ffmpeg_sources/ffmpeg && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix=/usr \
                --enable-gpl         \
                --enable-version3    \
                --enable-nonfree     \
                --disable-static     \
                --enable-shared      \
                --disable-debug      \
                --enable-libfdk-aac  \
                --enable-libfreetype \
                --enable-libx264     \
                --enable-libx265     \
                --enable-protocol=libsrt \
                --enable-libsrt && \
    make && \
    make install && \
    hash -r && \
    checkinstall -y --deldoc=yes && \
    ldconfig
    
# install obs dependencies
RUN  apt-get update -y \
    && apt install -y libnss3 \
    && apt-get clean -y

RUN cd ~ && git clone --recursive https://github.com/obsproject/obs-studio.git
RUN cd ~/obs-studio && TERM=xterm CI/linux/01_install_dependencies.sh

RUN apt install -y librist-dev

# compile OBS
RUN mkdir ~/obs-studio/build
RUN cd ~/obs-studio/build && \
    cmake -DENABLE_PIPEWIRE=OFF -DLINUX_PORTABLE=ON -DCMAKE_INSTALL_PREFIX="${HOME}/obs-studio-portable" -DENABLE_BROWSER=ON -DCEF_ROOT_DIR="../../obs-build-dependencies/cef_binary_5060_linux64" -DENABLE_AJA=0 ..

RUN export DEBIAN_FRONTEND=noninteractive && \
    cd ~/obs-studio/build && \
    make -j4 && \ 
    checkinstall --default --pkgname=obs-studio --fstrans=no --backup=no --pkgversion="$(date +%Y%m%d)-git" --deldoc=yes

# install obs
RUN mv /root/obs-studio-portable /usr/share/obs-studio
RUN echo "#!/bin/bash \n cd /usr/share/obs-studio/bin/64bit && /usr/share/obs-studio/bin/64bit/obs" > /usr/bin/obs.sh && chmod 770 /usr/bin/obs.sh

# Install Custom Theme
RUN git clone --branch develop https://github.com/luckydye/obs-modern.git
RUN mv ./obs-modern/* /usr/share/obs-studio/data/obs-studio/themes/

# Install NDI
# RUN wget -q -O /tmp/libndi4_4.5.1-1_amd64.deb https://github.com/Palakis/obs-ndi/releases/download/4.9.1/libndi4_4.5.1-1_amd64.deb \
# 	&& wget -q -O /tmp/obs-ndi_4.9.1-1_amd64.deb https://github.com/Palakis/obs-ndi/releases/download/4.9.1/obs-ndi_4.9.1-1_amd64.deb 
# RUN dpkg -i /tmp/*.deb && rm -rf /tmp/*.deb

# add VLC
# RUN add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe" \
#     && apt-get update -y \
#     && apt-get install -y vlc


RUN /etc/init.d/dbus start && /etc/init.d/avahi-daemon start

RUN echo "?package(bash):needs=\"X11\" section=\"DockerCustom\" title=\"OBS Screencast\" command=\"obs.sh\"" >> /usr/share/menu/custom-docker && update-menus

