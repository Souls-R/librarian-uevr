# Librarian VR

《Librarian: Tidy Up the Arcane Library!》的 UEVR 交互 Mod。

- 右手射线选书与交互，隐藏原准心。
- 稳定游戏镜头。
- 目标书名显示在射线落点附近，手中书名显示在右手旁。
- 书名 UI 防抖与平滑跟随。

## 安装

1. 下载并解压 [UEVR nightly-01143](https://github.com/praydog/UEVR-nightly/releases/tag/nightly-01143-4ee5c6b6162dee2291fc75f9dfc57667f6d45a2d)。
2. 从 [Releases](https://github.com/Souls-R/librarian-uevr/releases/latest) 下载 `Librarian-Win64-Shipping.zip`，在 UEVR 中点击 **Import Config** 导入。
3. Quest 通过 Steam Link 连接电脑，进入 SteamVR，再启动游戏。
4. 在 UEVR 中选择 `Librarian-Win64-Shipping`，运行时选择 **OpenVR**，点击 **Inject**。

每次重新启动游戏后重新注入，脚本会自动加载。

## 调整

编辑 `%APPDATA%\UnrealVRMod\Librarian-Win64-Shipping\data\librarian-pointer-settings.json`，可调整射线角度、书名位置和缓动。角度负值分别向左、向下调整；修改后自动生效。

基于 [praydog / UEVR](https://github.com/praydog/UEVR)。
