#!/bin/bash

# устанавливает среду для последующей компиляции, берет новые исходники зависимостей из github, но не собирает

DMD_VER=2.073.2
DUB_VER=1.2.0
GO_VER=go1.8.1

TARANTOOL_VER=1.7.3
MSGPUCK_VER=2.0

SMD=$PWD

# Get right version of DMD
if ! dmd --version | grep $DMD_VER ; then    
    wget http://downloads.dlang.org/releases/2.x/$DMD_VER/dmd_$DMD_VER-0_amd64.deb
    sudo dpkg -i dmd_$DMD_VER-0_amd64.deb
    rm dmd_$DMD_VER-0_amd64.deb
    rm -r ~/.dub
fi

# Get right version of DUB
if ! dub --version | grep $DUB_VER ; then
    wget http://code.dlang.org/files/dub-$DUB_VER-linux-x86_64.tar.gz
    tar -xvzf dub-$DUB_VER-linux-x86_64.tar.gz    
    sudo cp ./dub /usr/bin/dub
    rm dub-$DUB_VER-linux-x86_64.tar.gz
    rm dub
fi

# Get other dependencies
LIB_NAME[1]="libevent-pthreads-2.0-5"
LIB_NAME[3]="libevent-dev"
LIB_NAME[4]="libssl-dev"
LIB_NAME[5]="libmysqlclient-dev"
LIB_NAME[6]="cmake"
LIB_NAME[7]="libtool"
LIB_NAME[8]="pkg-config"
LIB_NAME[9]="build-essential"
LIB_NAME[10]="autoconf"
LIB_NAME[11]="automake"
LIB_NAME[12]="curl"

LIB_OK="Status: install ok installed"
F_UL=0

# install golang and dependency
if ! go version | grep $GO_VER ; then    
    mkdir tmp
    cd tmp
    wget https://storage.googleapis.com/golang/$GO_VER.linux-amd64.tar.gz
    tar -xvf $GO_VER.linux-amd64.tar.gz
    sudo rm -r /usr/local/go
    sudo rm /usr/bin/go
    sudo rm /usr/bin/gofmt
    sudo mv go /usr/local
    export GOROOT=/usr/local/go
    export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"
    echo 'export GOROOT=/usr/local/go'  >> ~/.bashrc
    echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin'  >> ~/.bashrc
    source ~/.bashrc
    go version
    cd ..
fi

export GOPATH=$HOME/go
echo 'export GOPATH=$HOME/go'  >> ~/.bashrc
source ~/.bashrc
go get github.com/gorilla/websocket
go get github.com/divan/expvarmon
go get gopkg.in/vmihailenco/msgpack.v2
cp -a ./source/golang-third-party/cbor $GOPATH/src
ls $HOME/go 

for i in "${LIB_NAME[@]}"; do

    L1=`dpkg -s $i | grep 'install ok'`

    if  [ "$L1" != "$LIB_OK" ]; then

	if [ $F_UL == 0 ]; then
	    sudo apt-get update
	    F_UL=1
	fi 

        sudo apt-get install -y $i
    fi

done

if ! ldconfig -p | grep libwebsockets; then

    # make libwebsockets dependency
    mkdir tmp
    wget https://github.com/warmcat/libwebsockets/archive/v2.0.3.tar.gz -P tmp
    cd tmp
    tar -xvzf v2.0.3.tar.gz
    cd libwebsockets-2.0.3
    mkdir build
    cd build
    cmake ..
    make
    sudo make install
    sudo ldconfig
    cd ..
    cd ..
    cd ..

fi

if ! ldconfig -p | grep libnanomsg; then

    # make nanomsg dependency
    mkdir tmp
    wget https://github.com/nanomsg/nanomsg/archive/1.0.0.tar.gz -P tmp
    cd tmp
    tar -xvzf 1.0.0.tar.gz
    cd nanomsg-1.0.0
    mkdir build
    cd build
    cmake ..
    make
    sudo make install

    echo '/usr/local/lib/x86_64-linux-gnu' > x86_64-linux-gnu-local.conf
    sudo cp x86_64-linux-gnu-local.conf /etc/ld.so.conf.d/x86_64-linux-gnu-local.conf
    sudo ldconfig

    cd ..
    cd ..
    cd ..

fi

if ! ldconfig -p | grep libtraildb; then

    sudo apt-get install -y libarchive-dev pkg-config
    sudo apt-get remove -y libjudydebian1
    sudo apt-get remove -y libjudy-dev

    mkdir tmp
    cd tmp

    wget https://mirrors.kernel.org/ubuntu/pool/universe/j/judy/libjudy-dev_1.0.5-5_amd64.deb \
     https://mirrors.kernel.org/ubuntu/pool/universe/j/judy/libjudydebian1_1.0.5-5_amd64.deb
    sudo dpkg -i libjudy-dev_1.0.5-5_amd64.deb libjudydebian1_1.0.5-5_amd64.deb


    wget https://github.com/traildb/traildb/archive/0.5.tar.gz -P tmp
    cd tmp
    tar -xvzf 0.5.tar.gz

    cd traildb-0.5
    ./waf configure
    ./waf build
    sudo ./waf install
    sudo ldconfig
    cd ..
    cd ..
    cd ..
fi

sudo apt-get remove -y libraptor2-0
ldconfig -p | grep libraptor2
if ! ldconfig -p | grep libraptor2; then

    sudo apt-get install -y gtk-doc-tools
    sudo apt-get install -y libxml2-dev
    sudo apt-get install -y flex
    sudo apt-get install -y bison

    mkdir tmp
    cd tmp

    wget https://github.com/dajobe/raptor/archive/raptor2_2_0_15.tar.gz -P .
    tar -xvzf raptor2_2_0_15.tar.gz

    cd raptor-raptor2_2_0_15
    #autoreconf -i
    ./autogen.sh
    make
    sudo make install
    sudo ldconfig
    cd ..
    cd ..
    cd ..

fi

if ! tarantool -V | grep $TARANTOOL_VER; then

curl http://download.tarantool.org/tarantool/1.7/gpgkey | sudo apt-key add -
release=`lsb_release -c -s`

# install https download transport for APT
sudo apt-get -y install apt-transport-https

# append two lines to a list of source repositories
sudo rm -f /etc/apt/sources.list.d/*tarantool*.list
sudo tee /etc/apt/sources.list.d/tarantool_1_7.list <<- EOF
deb http://download.tarantool.org/tarantool/1.7/ubuntu/ $release main
deb-src http://download.tarantool.org/tarantool/1.7/ubuntu/ $release main
EOF

# install
sudo apt-get update
sudo apt-get -y install tarantool
sudo apt-get -y install tarantool-dev

tarantool -V

fi

if ! ldconfig -p | grep libtarantool; then

    mkdir tmp
    cd tmp

    wget https://github.com/tarantool/tarantool-c/archive/3e022207513fc79fcde1e9da3d99511cef80c7df.tar.gz -P .
    tar -xvzf 3e022207513fc79fcde1e9da3d99511cef80c7df.tar.gz

    wget https://github.com/tarantool/msgpuck/archive/1.1.tar.gz -P third_party/msgpuck -P .
    tar -xvzf 1.1.tar.gz

    cp msgpuck-1.1/* tarantool-c-3e022207513fc79fcde1e9da3d99511cef80c7df/third_party/msgpuck 
    cd tarantool-c-3e022207513fc79fcde1e9da3d99511cef80c7df

    mkdir build
    cd build
    cmake ..
    make
    sudo make install
    sudo ldconfig

    cd ..
    cd ..

fi

   cd $SMD
   mkdir tmp
   cd tmp

   wget https://github.com/tarantool/msgpuck/archive/2.0.tar.gz -P third_party/msgpuck -P .
   tar -xvzf 2.0.tar.gz

   cd msgpuck-2.0    

   mkdir build
   cd build
   cmake ..
   make

   ls $SMD

   cp $SMD/tmp/msgpuck-2.0/build/libmsgpuck.a $SMD/source/lib64

   mkdir tmp
   cd tmp
   wget https://github.com/msgpack/msgpack-c/releases/download/cpp-2.1.1/msgpack-2.1.1.tar.gz
   tar -xvzf msgpack-2.1.1.tar.gz
   cd msgpack-2.1.1
   cmake .
   make
   sudo make install 
   cd ..
   cd ..
   rm -rf tmp

   cd $SMD/source/lib64/ext-lib-bind-src/v8_d
   make    

   #install HAPROXY
   sudo add-apt-repository ppa:vbernat/haproxy-1.5
   sudo apt-get update
   sudo apt-get install -y haproxy
   sudo cp ./haproxy.cfg /etc/haproxy/
   sudo service haproxy restart 
   
   #lmdb-go
   go get github.com/bmatsuo/lmdb-go/lmdb
   
   #fasthttp
   go get github.com/valyala/fasthttp

   export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib   
