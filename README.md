# mdwrap

一个纸糊的小工具。设计的初衷是，让 Neovim 硬断行时能够考虑到 [conceal](https://neovim.io/doc/user/syntax.html#%3Asyn-conceal) 的情况, 让文
文本能够在视觉上对齐。在实现的过程中，顺便添加了在中英文之间插入空白的功能。相对于，
通用的折行软件，本软件能够识别 Markdown 的特殊语法，比如：

- 不会对 YAML 头、代码块、独立公式等内容折行
- 折叠列表时，能够自动实现悬挂缩进
- 支持引用即引用的嵌套
- 支持 callout
- ...

目前，本软件的小目标是成为一个中文 markdown formatter, 能让人放心使用，在让文本变
得养眼的同时，无须担心文本的语法、文法和语义会被破坏。

目前，软件只提供一个有用的选项，是行宽（`--line-width`，默认是 `80`），将来代码重构时，
会陆续加上必要的配置选项，现在如果要个性化配置，只能修改代码、自己打补丁了。

## 安装

安装可以采用如下方式 :

```bash
perl Makefile.PL
make
make test
make install
```

如果系统有安装 [cpanm](https://metacpan.org/dist/App-cpanminus/view/bin/cpanm), 可以采用如下方式安装 :

```bash
cpanm .
```

当然，上述安装方法都需要先克隆本项目，然后进入项目文件夹。另外，应用可能会被安装到
`~/perl5/bin` 文件夹。需要确定 `$PATH` 是否包含此路径，或者自己链接文件。

## LICENSE AND COPYRIGHT

This software is Copyright (c) 2025 by Liu.Bian.Shi.

This is free software, licensed under:

The Artistic License 2.0 (GPL Compatible)

