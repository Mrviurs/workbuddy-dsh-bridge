@{
    # 换机时通常只需要改这个文件。
    # 复制本文件为 settings.psd1 后再改；settings.psd1 已被 .gitignore 排除，不会进仓库。
    CodebuddyCli  = '<WorkBuddy安装目录>\resources\app.asar.unpacked\cli\bin\codebuddy'
    PythonExe     = ''      # 留空自动探测：%LOCALAPPDATA%\Programs\Python\Python3* → PATH 里的 pythonw
    NodeExe       = ''      # 留空自动探测：PATH 里的 node → WorkBuddy 自带的 .workbuddy\binaries\node
    ServePort     = 8791
    RelayPort     = 8787
    DshHome       = ''      # 留空用 %USERPROFILE%\.dsh
}
