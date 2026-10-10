# AtomGit CLI Deb

华科 OpenAtom 俱乐部的 [AtomGit CLI](https://atomgit.com/hust-open-atom-club/atomgit-cli) 非官方 `.deb`。
目前只有 amd64

## 安装

从 [Releases](https://github.com/Nakanomk/atomgit-cli-deb/releases) 下载 `.deb`：

```sh
sudo apt install ./atomgit-cli_0.7.4-1_local3_amd64.deb
ag-cli version
```

升级时安装新 `.deb`，不要使用 `ag-cli update`。

## 本地构建

需要 Linux amd64、Go 1.26.8，以及 Bash、Git、GNU coreutils/findutils、binutils、dpkg-dev、jq、gzip、xz-utils。

```sh
bash ./build-deb.sh
```

输出在 `dist/`。脚本运行 Go 测试并校验最终包，不需要 root；源码和 Go 依赖已包含，可离线构建。

## 许可

新增打包脚本、工作流及文档采用 [MulanPSL-2.0](LICENSE)。上游代码见 `src/LICENSE`，第三方组件保留各自许可证。
