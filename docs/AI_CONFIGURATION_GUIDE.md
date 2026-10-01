# 灵感菇 AI 配置指南

灵感菇支持 OpenAI-compatible Chat Completions 接口。你需要准备三个值：
Base URL、模型 ID 和 API Key。

## OpenAI 官方接口

1. 登录 [OpenAI Platform](https://platform.openai.com/)。
2. 在 [API Keys](https://platform.openai.com/api-keys) 创建 API Key。
3. 在灵感菇的“AI 设置”中填写：

| 字段 | 填写内容 |
| --- | --- |
| Base URL | `https://api.openai.com` |
| 模型名称 | 你的 Platform 项目实际可用、且支持 Chat Completions 的模型 ID |
| API Key | 刚刚创建的 Platform API Key |

模型名称必须是精确 ID，不是“ChatGPT”“Plus”之类的产品名称。可从
[OpenAI 模型目录](https://developers.openai.com/api/docs/models)查看模型说明。

ChatGPT 登录或订阅不能直接作为这里的 API Key。灵感菇调用的是 OpenAI API
Platform，费用与额度由对应 API 项目管理。

## 第三方 OpenAI-compatible 服务

请从服务商自己的 API 文档或控制台复制：

| 字段 | 填写内容 |
| --- | --- |
| Base URL | 服务商提供的根地址，或以 `/v1` 结尾的地址 |
| 模型名称 | 服务商给出的精确模型 ID |
| API Key | 服务商控制台创建的密钥 |

灵感菇会自动补上 `/v1/chat/completions`。如果地址已经包含 `/v1`，不会重复拼接。
不要把 OpenAI 的模型 ID 或 API Key 填到另一家服务商的接口中。

## 本地模型服务

本地服务必须启用 OpenAI-compatible Chat Completions 接口。例如：

| 字段 | 示例 |
| --- | --- |
| Base URL | `http://127.0.0.1:11434/v1` |
| 模型名称 | 本地服务中已经加载的精确模型 ID |
| API Key | loopback 地址可以留空 |

端口 `11434` 只是示例，请使用本地服务实际监听的地址。

## 正确操作顺序

1. 填写三个字段。
2. 点击“保存设置”。保存本地配置不依赖网络。
3. 点击“测试连接”。测试可能消耗少量 token。
4. 连接成功后，再开启自动整理或进入 AI 工作台。

## 常见错误

- `401`：API Key 无效、被撤销或粘贴时带了多余空格。
- `403`：密钥或项目没有使用该模型的权限。
- `404`：Base URL、`/v1` 路径或模型名称不正确。
- `429`：项目额度不足，或请求过于频繁。
- 超时/断网：配置仍可保存，本地灵感记录不受影响。

## 密钥和隐私

- API Key 只保存在 macOS Keychain。
- 数据库、日志和导出文件不包含 API Key。
- 第一次向新的服务主机发送灵感前，灵感菇会显示域名、范围和记录数量并要求确认。
- 自动整理与自动总结默认关闭。

官方参考：

- [OpenAI Developer Quickstart](https://developers.openai.com/api/docs/quickstart)
- [OpenAI API Models](https://developers.openai.com/api/docs/models)
- [OpenAI API Overview](https://developers.openai.com/api/reference/overview)
