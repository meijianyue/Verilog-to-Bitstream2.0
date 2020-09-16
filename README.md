# VTR-to-Bitstream2.0
VTB的依赖工具、搭建步骤、环境配置、遇到的问题及解决办法

## VTB依赖的工具
>* VTR 7.0 (下载地址：https://github.com/verilog-to-routing/vtr-verilog-to-routing/releases/tag/vtr_v7)
>* vtr-to-bitstream_v2.1.patch (下载地址：https://github.com/eddiehung/eddiehung.github.io/releases/tag/vtb_v2.1)
>* Torc-1.0 (下载地址：http://svn.code.sf.net/p/torc-isi/code/tags/torc-1.0)
>* Yosys-0.9 (下载地址：http://www.clifford.at/yosys/download.html)
>* Xilinx ISE 14.7 for Linux (官网下载:https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/archive-ise.html)

## 搭建步骤：
>>* 1. 下载VTR 7.0，在进行后续步骤之前先编译试试，编译通过后再进行下一步。（我们 make 时就报错了，后面讲遇到的问题时会详细介绍）
>>* 2. 下载补丁vtr-to-bitstream_v2.1.patch，放在VTR7.0目录下（指VTR7.0文件夹下，后同），执行命令：patch -p1 < vtr-to-bitstream_v2.1.patch
>>* 3. 将torc-1.0和yosys-yosys-0.9放入VTR7.0目录下，分别重命名为"torc"和"yosys"
>>* 4. 配置运行环境（见下文）
>>* 5. 下载Xilinx ISE 14.7，必须要full license（安装时注意环境：ubuntu-32位，安装教程可自行百度）
>>* 6. 配置环境变量，我们需要的只是ISE的xdl2ncd和bitgen等模块，且需要在命令行直接调用这些模块，因此需要配置环境变量：
        export PATH=$PATH:pathTo/Xilinx/14.7/ISE_DS/ISE/bin/lin  #pathTo由ISE的下载路径决定
>>* 7. 在VTR7.0目录下执行 make 

## 运行环境配置
>>* VTR7.0编译时依赖一系列的包，torc工具编译时需要gcc、Boost和Subversion，yosys编译时需要clang和git，如下所示：
        -- ubuntu-16.04.6-desktop-i386.iso (32位)  <br>
        -- gcc 5.4.0 20160609 (Ubuntu 5.4.0-6ubuntu1~16.04.12)  <br>
        -- clang version 3.8.0-2ubuntu4 (tags/RELEASE_380/final)  <br>
        -- Subversion 1.9.3  <br>
        -- boost-1.54.0  <br>
        -- git 2.7.4  <br>
     
>> 参考VTR8.0的手册，VTR运行需要配置如下包：
（注意：VTR7.0的编译和运行其实只需要下述包中的几个，大部分可不必下载，如果需要节省内存，可以先不下载下述包，直接执行编译，然后根据报错时出现的提示下载所缺的包。）
```Bash
    sudo apt-get install \
      build-essential \
      flex \
      bison \
      cmake \
      fontconfig \
      libcairo2-dev \
      libfontconfig1-dev \
      libx11-dev \
      libxft-dev \
      libgtk-3-dev \
      perl \
      liblist-moreutils-perl \
      python 
```
>>> 用于文件生成的包：
```Bash
    sudo apt-get install \
      doxygen \
      python-sphinx \
      python-sphinx-rtd-theme \
      python-recommonmark
```
>>> 开发依赖包：
```Bash
    sudo apt-get install \
      git \
      valgrind \
      gdb \
      ctags
```

## 编译遇到的问题及解决办法
### VTR7.0预编译
    前面搭建步骤中提到过，下载VTR7.0后需要预先编译，以预先解决部分编译问题。
>> 打开终端，进入`VTR7.0`根目录，执行make <br>
>> 可能会出现的错误： <br>
>>>* 编译odin时报错：对“ODIN/SRC/simulate_blif.c”文件中一些函数“未定义的引用”
    这些函数定义时前面都有"inline"关键字，在gcc编译过程中，该关键字最好不要出现在.c文件的函数定义中，原因自行百度。因此，只需在该.c文件中找到所有报错的函数的定义，去掉"inline"关键字即可。 
    
>>>* 编译abc时报错：“src/misc/espresso/unate.c”文件中关于"restrict"的error  <br>
    gcc 5.4.0版本编译时，restrict被识别为关键字，不能用作变量或者函数参数名。将所有“restrict”改为“_restrict”即可。  <br>

>>>* 编译ace2时报错：文件“ace2/ace.c”里的函数‘print_status’中，对‘Ace_ObjInfo’未定义的引用  <br>
    还是"inline"关键字的问题，将函数“Ace_ObjInfo”定义前面的inline去掉即可。  <br>

>>>* 注意事项：vpr工具提供图形化界面，如果在编译后想要执行vtr流程并查看图形化界面，可修改 vpr/Makefile 文件中的参数：  <br>
    ENABLE_GRAPHICS = true  <br>
    
### VTB编译
    配置好VTB的依赖包和运行环境后，在 “VTR7.0” 根目录下执行 make，完成整个VTR-to-Bitstream的编译。期间会遇到诸多编译错误，对于因缺少某些依赖库而引起的错误，这里不多介绍，可以百度解决。本节仅对部分较难解决的错误给出解决方法。
>> 打开终端，进入`VTR7.0`根目录（此时实际上是VTB2.0），执行make <br>
>> 可能出现的错误：  <br>
>>>* 编译torc时报错： <br>
    1. 如果在执行“cd torc && svn cleanup && svn up”时报错："client version is old ..."（类似这样），是由于
Subversion版本过低，需要更新至更高版本。  <br>
    2. 如果在执行“cd torc && svn cleanup && svn up”时报错："...不是副本目录"，可采取如下做法： <br>
    （1）打开torc文件，按找到隐藏文件.svn(ctrl+h可查看隐藏文件)，把他删除  <br>
    （2）在“VTR7.0”根目录下(torc文件所在目录)执行命令：svn checkout http://svn.code.sf.net/p/torc-isi/code/tags/torc-1.0 torc   <br>
    （3）此时会生成新的.svn文件，下载最新torc需要较长时间（因为我们之前下载的torc已是最新版本，.svn文件生成后可以直接中断下载(Ctrl+c))  <br>
    （4）再次在“VTR7.0”根目录执行 make ，svn升级torc时会产生冲突，直接选择“(r)mark resolved”即可。原因是svn的锁机制，前面中断下载后，小部分中断前正在下载的文件夹会被锁住，我们并未找到它们并执行"svn clean up"，但是这不影响后续编译和运行  <br>
    
>>>* 编译yosys时会报错：  <br>
    1. 关于"tcl.h"的报错，需要下载"tcl8.6-dev"包  <br>
    2. 关于"readline.h"的报错，需要下载“libreadline-dev”包  <br>
    3. 有些.hpp文件报错：‘uint32_t/uint8_t/uint16_t’ has not been declared，在相应头文件里加上“#include <inttypes.h>”  <br>
    4. “Flattening.cpp”报错：关于函数重定义，默认参数的错误，原因是c++中，在声明和定义含默认参数的函数时，声明、定义中只有一个能包含默认参数：  <br>
    错误写法:  <br>  
        int add(int a, int b=10);  //函数声明   <br>
        int add(int a, int b=10) {...} //函数定义  <br>
    正确写法:  <br>
        int add(int a, int b);  //函数声明  <br>  
        int add(int a, int b=10) {...} //函数定义  <br>
    类似地，报错的函数的声明和定义中都有默认参数，找到其在Flattening.hpp头文件中的函数声明，去掉 “ =默认参数值” 即可  <br>
    5. 报错：torc/src/torc/generic/edif/Decompiler.cpp:37:13: error: ‘std::__cxx11::string {anonymous}::trimLeading(const string&)’ defined but not used [-Werror=unused-function] , 删除文件“/torc/src/torc/Makefile.targets”中第59行: "-Werror \"即可。这里只是某个函数定义了却未使用的警告，因为有“-Werror”，所有警告被当作错误，故去掉即可。  <br>
    6. 关于"git clone"的报错，yosys编译时会从github上下载abc文件，若网速太慢会下不了，继而连接超时报错。建议用其他方法下载完毕后放入yosys文件，具体下载地址在yosys/Makefile中可以找到  <br>
    
注意：如果clang或者其他依赖包的版本与ubuntu16的默认版本不同，可能会报许多奇怪的错误。可以慢慢找解决方案，最好还是保持版本一致。 <br>

>>>* 编译Xilinx ISE提供的bit流生成模块时报错  <br>
    1. 第一种错误是找不到"partgen"的路径，这就是前面搭建步骤中最后一步环境变量有问题，需要正确配置  <br>
    2. 第二种错误：Can't locate File/Which.pm in @INC (you may need to install the File::Which module) ，执行命令"cpan File::Which"安装即可  <br>


到这里整个编译就完成了。我们可以测试一下VTB能否从.v文件顺利生成.bit文件，新建一个test文件夹，在终端进入该文件夹后执行命令：  <br>
```Bash
    $VTR_ROOT/vtr_flow/scripts/run_vtr_flow.pl $VTR_ROOT/vtr_flow/benchmarks/verilog/mkPktMerge.v \                
    $VTR_ROOT/vtr_flow/arch/xilinx/xc6vlx240tff1156.xml
    # $VTR_ROOT表示"VTR7.0"根目录
```
