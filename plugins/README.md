# StarCompute 插件安装指南

## 概述

StarCompute 使用模块化插件系统，每个用户可以独立配置需要的插件。插件目录结构如下：

```
plugins/
├── README.md              # 本文件
├── file-upload/           # 文件上传插件
├── code-interpreter/      # 代码执行插件
├── web-search/            # 网络搜索插件
├── document-parser/       # 文档解析插件
├── image-generation/      # 图像生成插件
└── knowledge-base/        # 知识库插件
```

## 安装插件

### 方法一：同步到所有用户

```bash
# 同步所有插件
sudo ./scripts/sync_plugins.sh

# 同步指定插件
sudo ./scripts/sync_plugins.sh file-upload
```

### 方法二：手动安装到单个用户

```bash
# 复制插件到用户目录
cp -r plugins/file-upload /home/<username>/.dsh/plugins/

# 设置权限
chown -R <username>:<username> /home/<username>/.dsh/plugins/
```

## 插件配置

每个用户的插件配置位于 `~/.dsh/config/cordis.patch.yml`。编辑此文件启用/禁用插件：

```yaml
plugins:
  file-upload:
    enabled: true    # 设为 false 禁用
    # ... 其他配置
```

## 添加自定义插件

1. 在 `plugins/` 目录下创建新的插件目录
2. 创建 `index.js` 作为插件入口
3. 在 `templates/package.json` 中注册插件 bundle
4. 运行 `sync_plugins.sh` 同步到所有用户

### 插件目录结构

```
my-plugin/
├── index.js        # 插件入口
├── manifest.json   # 插件元信息
└── README.md       # 插件说明
```

### manifest.json 示例

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "我的自定义插件",
  "capabilities": ["my-cap"],
  "entry": "index.js"
}
```

## 已有插件说明

### file-upload
文件上传与管理插件，支持多种文件格式的上传、读取和管理。

### code-interpreter
代码执行插件，支持 Python、JavaScript、Bash 代码的在线执行和调试。

### web-search
网络搜索插件，集成 SearXNG 搜索引擎，支持实时网络信息检索。

### document-parser
文档解析插件，支持 PDF、DOCX、XLSX、PPTX 等格式的解析和内容提取。

### image-generation
图像生成插件，可对接 Stable Diffusion WebUI 或其他图像生成服务。

### knowledge-base
知识库插件，基于 ChromaDB 向量数据库，支持文档索引和语义检索。

## 故障排除

### 插件未生效

1. 检查插件目录权限：`ls -la /home/<username>/.dsh/plugins/`
2. 检查配置文件：`cat /home/<username>/.dsh/config/cordis.patch.yml`
3. 重启 dsh 服务：`sudo systemctl restart dsh-user@<username>`

### 权限问题

```bash
sudo chown -R <username>:<username> /home/<username>/.dsh/
sudo chmod -R 755 /home/<username>/.dsh/plugins/
```

### 查看日志

```bash
journalctl -u dsh-user@<username> -f
```
