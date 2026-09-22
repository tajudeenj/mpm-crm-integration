#!/bin/sh
echo "Compiling CRM Admin Tool..."
javac -encoding UTF-8 -source 8 -target 8 -cp ojdbc8.jar CrmAdminTool.java EncryptPassword.java
if [ $? -eq 0 ]; then
    echo "============================================="
    echo "  Compile SUCCESS -- ready to run"
    echo "============================================="
else
    echo "============================================="
    echo "  Compile FAILED -- check errors above"
    echo "============================================="
fi
