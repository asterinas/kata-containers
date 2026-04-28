我需要你给当前仓库添加一些CI。

https://github.com/jjf-dev/asterinas/pull/57这个PR里面添加了一些脚本和一个CI。这个仓库虽然和当前对应的代码不一样，但是这些脚本并不依赖那个仓库的代码。

1. 我现在希望把那个CI添加到当前的仓库，包括那个PR里用到的所有脚本和workflow文件。脚本你可以放在tools/kata的下面。workflow
2. 此外，我还希望你修改release-asterinas这个workflow可以修改一下，把那些脚本也放在release里面
3. 我希望你在加个新的workflow，可以基于asterinas/asterinas的基础仓库（版本号基于https://github.com/asterinas/asterinas仓库），执行1中你可以找到的kata_env.sh脚本，在基础仓库里面把环境加上(命令大概是kata_env.sh install)，并且把1中所有的脚本也放到容器内的/root/asterinas/tools/kata下面。最后生成一个新的asterinas/asterinas-kata的镜像，然后推到docker hub上。

为了方便测试，你可以把所有workflow都改成PR或者push会触发，你可以自己去https://github.com/jjf-dev/kata-containers这个仓库下开PR，然后观察CI的运行情况。不用尝试在本地调试，本地网络不好

记得随时留下日志，你得出了任何结论或者有任何进展，请都用md的方式记录下来，我会随时review进展
