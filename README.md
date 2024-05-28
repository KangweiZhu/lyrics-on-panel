# Plasma6-Lyric-on-panel
> 适配最新的 **Plasma6** 桌面环境, Plasma5版本请移步 **master branch**
> **近乎完美地**实现了 MacOS 下 网易云音乐 的 歌词顶栏显示 功能
>
> MacOS原效果参考：https://blog.csdn.net/weixin_34061200/article/details/112693092 或自行下载网易云音乐进行对比。
>
> ![Lyric-on-panel效果](img/image-20240317195128194.png "Lyric-on-panel")**lyrics-on-panel-plasma5 效果**
>
> ![image-20240529024709115](../img/image-20240529024709115.png)**lyrcis-on-panel-plasma6 + panel colorizer效果。**
>
> ![网易云音乐效果](https://img-blog.csdnimg.cn/img_convert/d98c4b5b7d938727d008214573453c57.png "网易云音乐效果")**MacOS网易云音乐效果**
>
> 采用两套逻辑： 
>
>  	1. YesPlayMusic （YPM）： 直接从 YPM 暴露在本地的端口获取 当前播放歌曲的歌词
>  	2. Compatible（兼容）： 从 Lrclib开源 歌词数据库中 通过（歌手，曲名，专辑名）fetch歌词。 若 不存在这三个参数的 精确匹配的结果，则用歌曲名做一次模糊查询
>
> 通过 Mpris2数据源 获取当前播放音乐的所属媒体源。兼容模式理论适用于**所有正确实现了 Mpris2 规范的播放器**。其中包括通过 Google Chrome 在线播放的流媒体平台。兼容模式下， 主流歌曲 **歌词匹配成功率** **超过95%**



## 0. Change Log

See here: [ChangeLog](./ChangeLog.md)



## 1. Installation Guide

As for installing the widget, you will have 2 approaches:

1. Use the GUI operation recommended by the KDE official website at [this link](https://userbase.kde.org/Plasma/Installing_Plasmoids).

2. In the terminal, type `kpackagetool5 -t Plasma/Applet -i xxxx`, replacing `xxxx` with the path to your extracted folder. e.g. `/home/anicaa/.local/share/plasma/plasmoids/lyrics-on-panel-master`. If you already install this widget, or you failed to install this widget, please try `kpackagetool5 -t Plasma/Applet -r xxxx`

   

## 2. Screenshots

### 2.1 Fullscreen Shortcuts

* Under Plasma6 (With Panel Colorizer).

> "Most likely will be able to display the lyric that that Spotify does not show."

![image-20240529024104188](../img/image-20240529024104188.png)

* Under Plasma5

![image-20240317192855544](img/image-20240317192855544.png "Fullscreen shortcut")

---

### 2.2 Panel Only

![image-20240317192935566](img/image-20240317192935566.png "Panel shortcut")

![image-20240529023754367](../img/image-20240529023754367.png)

![image-20240529023819659](../img/image-20240529023819659.png)

---

### 2.3 Synchronized lyrics 

![image-20240317192959997](img/image-20240317192959997.png "synchronized lyrics")

---

### 2.4 Freedom of Customizing every component of this widget

![image-20240529023657784](../img/image-20240529023657784.png)

---
