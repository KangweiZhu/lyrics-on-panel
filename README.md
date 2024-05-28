# Plasma5-Lyric-on-panel

### 0. Developer Notes for Plasma5
> For plasma6, move here https://github.com/KangweiZhu/lyrics-on-panel/tree/plasma6.

> As we can see, up to 5/20/2024, several popular Linux distributions have updated their stable channels from the Plasma 5 environment to Plasma 6. The **API related to MPRIS2 in Plasma 6** has changed and is definitely buggy, as many software, such as Spotify, seem not to **implement it correctly**. However, embracing new versions is the motto of all rolling release distributions. The next step is since this widget received approximately **800+ downloads in total** in one and a half months (which is definitely good for a pet project), I will try to refactor or at least optimize the codebase of the Plasma 5 version of this widget. Then, I will cease updates for Plasma 5 and focus on fixing known defects and adding features to the Plasma 6 version.



> 在KDE下， 复刻了 MacOS网易云音乐桌面端 的 歌词顶栏显示 功能
>
> MacOS原效果参考：https://blog.csdn.net/weixin_34061200/article/details/112693092， 或自行下载网易云音乐进行对比。
>
> ![Lyric-on-panel效果](img/image-20240317195128194.png "Lyric-on-panel")
>
> ![网易云音乐效果](https://img-blog.csdnimg.cn/img_convert/d98c4b5b7d938727d008214573453c57.png "网易云音乐效果")
>
> 歌词同步采用两套逻辑： 
>
>  	1. YesPlayMusic （YPM）： 直接从 YPM 暴露在本地的端口获取 当前播放歌曲的歌词
>  	2. Compatible（兼容）： 从 Lrclib开源 歌词数据库中 通过（歌手，曲名，专辑名）fetch歌词。 若 不存在这三个参数的 精确匹配的结果，则用歌曲名做一次模糊查询
>
> 通过 Mpris2 数据源 获取当前播放音乐的所属媒体源。兼容模式 理论适用于**所有正确实现了 Mpris2 规范的播放器**，包括通过 Google Chrome， FireFox 访问的在线流媒体平台。兼容模式下， 主流歌曲 **歌词匹配成功率** **超过95%**



### 1. Installation Guide

As for installing the widget, you will have 2 approaches:

1. Use the GUI operation recommended by the KDE official website at [this link](https://userbase.kde.org/Plasma/Installing_Plasmoids).

2. In the terminal, type `kpackagetool5 -t Plasma/Applet -i xxxx`, replacing `xxxx` with the path to your extracted folder. e.g. `/home/anicaa/.local/share/plasma/plasmoids/lyrics-on-panel-master`.



## 2. Widget Showcase

* Under Fullscreen 

![image-20240317192855544](img/image-20240317192855544.png "Fullscreen shortcut")

* Panel Only

![image-20240317192935566](img/image-20240317192935566.png "Panel shortcut")



* Synchronized lyrics (Even more precise then Spotify!)

![image-20240317192959997](img/image-20240317192959997.png "synchronized lyrics")



* Freedom of Customizing every component of this widget

![image-20240317193415515](img/image-20240317193415515.png)





