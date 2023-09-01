FROM ubuntu:22.04 as basesystem

RUN apt update \
    && apt-get install -y wget git

RUN mkdir -p /app/Dev
WORKDIR /app/Dev

FROM basesystem as downloadopencv

RUN apt-get install -y unzip

RUN mkdir -p OpenCV && cd OpenCV \
    && wget https://github.com/opencv/opencv_contrib/archive/refs/tags/4.8.0.zip \
    && unzip 4.8.0.zip -d opencv_contrib \
    && rm 4.8.0.zip

RUN cd OpenCV \
    && git clone https://github.com/opencv/opencv.git \
    && cd opencv
RUN cd OpenCV/opencv \
    && git checkout f9a59f2592993d3dcc080e495f4f5e02dd8ec7ef \
    && mkdir build 


FROM basesystem as downloadpangolin

RUN git clone https://github.com/stevenlovegrove/Pangolin.git \
    && cd Pangolin \
    && git checkout aff6883c83f3fd7e8268a9715e84266c42e2efe3 \
    && mkdir build


FROM basesystem as downloadorbslam3

# COPY . ./ORB_SLAM3
# RUN cd ORB_SLAM3
# Or clone git repository
RUN git clone https://github.com/MrHag/ORB_SLAM3 \
    && cd ORB_SLAM3 


FROM basesystem as buildpackages

RUN apt update -y \
    && apt-get install build-essential libglew-dev python3-dev python3-numpy libavcodec-dev libavformat-dev libswscale-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev libgtk-3-dev libeigen3-dev -y 


FROM buildpackages as cmake
RUN apt-get install -y cmake

FROM cmake as cv48

COPY --from=downloadopencv /app/Dev /app/Dev/

WORKDIR /app/Dev/OpenCV/opencv/build

RUN cmake -D CMAKE_BUILD_TYPE=Release -D WITH_CUDA=OFF BUILD_EXAMPLES=OFF -D BUILD_DOCS=OFF -D BUILD_PERF_TESTS=OFF -D BUILD_TESTS=OFF -D CMAKE_INSTALL_PREFIX=/usr/local -DOPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/opencv_contrib-4.8.0/modules ..
RUN make -j 4
RUN make DESTDIR=/app/Dev/OpenCV/opencv/build/dest install


FROM cmake as pangolin

COPY --from=downloadpangolin /app/Dev /app/Dev/

WORKDIR /app/Dev/Pangolin/build

RUN cmake -D CMAKE_BUILD_TYPE=Release .. \
    && make -j 4
RUN make DESTDIR=/app/Dev/pangolin/build/dest install

FROM buildpackages as orbslam3

RUN apt-get install -y cmake libboost-all-dev libssl-dev

ARG orbslam_dir=/app/Dev

COPY --from=downloadorbslam3 /app/Dev $orbslam_dir

WORKDIR $orbslam_dir/ORB_SLAM3

COPY --from=cv48 /app/Dev/OpenCV/opencv/build/dest /
COPY --from=pangolin /app/Dev/pangolin/build/dest /

RUN ldconfig

RUN echo "Configuring and building Thirdparty/DBoW2 ..." \
    && cd Thirdparty/DBoW2 \
    && mkdir build \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j 4

RUN echo "Configuring and building Thirdparty/g2o ..." \
    && cd Thirdparty/g2o \
    && mkdir build \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j 4

RUN echo "Configuring and building Thirdparty/Sophus ..." \
    && cd Thirdparty/Sophus \
    && mkdir build \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j 4

RUN echo "Uncompress vocabulary ..." \
    && cd Vocabulary \
    && tar -xf ORBvoc.txt.tar.gz 

RUN echo "Configuring and building ORB_SLAM3 ..." \
    && mkdir build \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j 4

FROM ubuntu:22.04
ARG orbslam_dir=/app/Dev
COPY --from=orbslam3 /app/Dev/ORB_SLAM3 $orbslam_dir/ORB_SLAM3
COPY --from=cv48 /app/Dev/OpenCV/opencv/build/dest $orbslam_dir/opencv
COPY --from=pangolin /app/Dev/pangolin/build/dest $orbslam_dir/pangolin
ENTRYPOINT ["tail"]
CMD ["-f","/dev/null"]
