# 丹青阅读 · Flutter 电子书阅读器

Windows 桌面端 + 安卓 App 的本地电子书阅读器，纯 Flutter 实现，白色简洁风格。

## 直接运行

```
build\windows\x64\runner\Release\novel_reader.exe
```

双击即可，无需安装 Flutter。整个 `Release` 文件夹可以整体拷走。

## 功能

**格式**：TXT / MD（UTF-8 / UTF-16 / GBK 自动识别）、EPUB（自实现 ZIP + OPF/NCX 解析）、MOBI / AZW3 / AZW（PalmDOC LZ77，不支持 DRM）

**首页**
- 最近阅读横滑区：封面、书名、阅读进度，点一下直接续读
- 右上角「+」菜单：从本地导入（多选文件）、从本地文件夹导入（整目录扫描）、从云端导入（OneDrive 选书下载）、书库管理
- 四个二级入口（各自独立页面）：我的喜爱 / 最近添加 / 最近阅读 / 回收站
- 书库抽屉：独立滚动，不影响上方最近阅读与入口的布局
- 布局切换（紧凑 / 宽松）、排序（导入时间 / 查看时间，正序倒序）
- 卡片右上角心形收藏，长按移入回收站
- 封面：EPUB 读 OPF、MOBI/AZW3 读 EXTH 自动提取真实封面并缓存；TXT/MD 若同目录有同名图片也会使用，否则回退文字封面

**外部打开（双击即读）**
- Windows：注册表登记「打开方式」，在资源管理器里双击 `.txt / .md / .epub / .mobi / .azw3 / .azw` 可直接用本应用打开；已开窗口时会把文件交给当前实例
- 安卓：文件管理器里点电子书 →「打开方式」出现「丹青阅读」，冷启动和运行中都支持
- 外部文件会复制进书库并自动入库、打开阅读页

**书架**：搜索、多书架（新建 / 重命名 / 删除）、刷新、书籍归入指定书架

**书库管理**（首页「+」→ 书库管理）：查看书库路径、打开文件夹、扫描导入新书、清理无效记录、清理重复记录

**阅读页（内容层 + 菜单层）**
- 内容层：顶部常驻当前章节标题；底部状态栏显示电量、时间、书名，右下角显示全书进度
- 点屏幕中间展开菜单层：左上返回，顶栏「选项」（字号 / 夜间模式 / 护眼模式）与右上「搜索」全书
- 底栏：目录、书签、主题设置；最下方全书 0–100% 可拖动进度条
- 书签：记录所在章节与位置，可添加、跳转、删除，按账户单独存储
- 搜索：跨章节关键词搜索，点结果直接跳到命中位置
- 按行精确分页、点击左右翻页、左右滑动翻页、键盘方向键 / PgUp/PgDn
- 5 套主题、5 种字体、字号 / 行距 / 边距可调，翻页风格可选滑动 / 淡入 / 无动画
- 进度记忆：章节 + 章内偏移，退出再打开回到原处

**本地账户**：注册 / 登录 / 退出，SHA-256 + 随机盐，只存本机；每个账户独立书库索引与阅读进度，未登录为游客

**云同步（OneDrive）**
- 设置 → 云同步 → 点「登录 OneDrive」，弹浏览器登录微软账号，授权后自动回到 App
- 内置公共客户端（Microsoft Graph Command Line Tools），**不需要自己去 Azure 申请 client_id**；也保留「高级」入口可填自己的 client_id
- 书籍同步到 OneDrive 的 `Apps/DanQingReader/books`
- 支持立即上传、从云端下载、启动时自动同步

## 数据位置

| 内容 | 路径 |
|---|---|
| 书库（电子书原始文件） | `%USERPROFILE%\Documents\丹青阅读\书库` |
| 应用数据（账户 / 书架 / 索引 / 设置 / 令牌） | `%APPDATA%\DanQingReader` |
| 封面缓存 | `%APPDATA%\DanQingReader\covers` |

首次启动会自动放入一本示例小说《青崖记》。

## 源码结构

```
lib/
  main.dart                    入口
  models/book.dart             Book · Chapter 数据模型
  services/
    app_paths.dart             数据目录与书库目录
    app_settings.dart          通用设置（方向 / 语言 / 排序 / 布局 / 自动同步）
    auth_service.dart          本地账户
    library_service.dart       书库索引 · 导入 · 扫描 · 回收站 · 进度
    one_drive_service.dart     OneDrive OAuth(PKCE) · 上传 · 下载
    shelf_service.dart         多书架
    reader_settings.dart       阅读样式持久化
    password_hasher.dart       SHA-256 / HMAC
    text_codec.dart            编码识别（含 GB18030）
    chapter_parser.dart        章节切分 · 书名作者识别
    book_parser.dart           各格式解析入口
    epub_parser.dart           EPUB
    mobi_parser.dart           MOBI / AZW3
    cover_service.dart         封面提取与缓存
    open_file_service.dart     接收「打开方式」传入的文件
  reader/
    paginator.dart             按行分页
    reader_page.dart           阅读页
    reader_sheets.dart         目录 / 阅读设置弹层
  ui/
    app_theme.dart             颜色与主题
    main_shell.dart            底部三栏导航
    home_page.dart             首页（四个二级入口 + 全部书籍）
    library_list_page.dart     我的喜爱 / 最近添加 / 最近阅读 / 回收站
    library_manager_page.dart  书库管理
    import_sheet.dart          「+」添加来源菜单
    shelf_page.dart            书架
    settings_page.dart         设置（账户 / 通用 / 阅读偏好 / OneDrive / 关于）
    book_detail_page.dart      书籍详情
    book_cover.dart            封面（真实图片 / 文字回退）
    auth_sheet.dart            登录注册弹层
tool/
  gbk_check.dart               GBK 解码与章节切分校验
  shelf_check.dart             对书库真实文件跑解析器
  format_check.dart            各格式解析校验
  make_sample_epub.dart        生成示例 EPUB
```

## 重新构建

```powershell
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat build windows --release
C:\src\flutter\bin\flutter.bat build apk --release
```

产物：
- Windows：`build\windows\x64\runner\Release\novel_reader.exe`
- 安卓：`build\app\outputs\flutter-apk\app-release.apk`
