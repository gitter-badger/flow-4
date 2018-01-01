cd nanomsg
rd /S /Q build
rd /S /Q build64
rd /S /Q ..\..\..\..\dist\x86_64\debug\nanomsg
rd /S /Q ..\..\..\..\dist\x86_64\release\nanomsg
copy /Y ..\nanomsg.CMakeLists.txt CMakeLists.txt

md build64
cd build64
cmake .. -G "Visual Studio 14 2015 Win64" -DNN_STATIC_LIB=ON
cmake --build . --config Release
cd ..
md ..\..\..\..\dist\x86_64\debug\nanomsg
copy /Y build64\Release ..\..\..\..\dist\x86_64\debug\nanomsg
md ..\..\..\..\dist\x86_64\release\nanomsg
copy /Y build64\Release ..\..\..\..\dist\x86_64\release\nanomsg

rd /S /Q build
rd /S /Q build64
cd ..