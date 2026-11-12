# Penna API 配置指南(供 AI 助手使用)

> 使用方法:把这份文档整个发给任意 AI 助手,再告诉它你用的是哪家服务、手上有哪些信息,让它按本文档一步步带你在 Penna 里填好 API。

---

## 给 AI 助手的说明

你将协助用户在 **Penna 羽毛笔**(Windows 桌面端的文生图提示词工作台)中配置大模型 API。请遵守以下规则:

1. **API Key 只由用户本人填进 Penna。** 不要让用户把 Key 发到对话里;如果用户发了,提醒他到服务商后台作废这个 Key 并重新生成。
2. 先问清三件事:用的是哪家服务(或本地程序)、这家服务兼容 OpenAI 接口还是 Google 接口、想用哪个模型。
3. 按下文「需要填写的字段」逐项给出要填的值,最后给出一份核对清单。
4. 不确定的模型名称,不要凭记忆编写:让用户在 Penna 里点「拉取模型」从列表中勾选,或以服务商当前文档为准。
5. 用户报错时,按「常见报错」一节对照原因。

---

## 配置入口

Penna 左侧图标栏最下方的齿轮 →「设置」→「**API 管理**」。

- 页面顶部的「**Agent 对话**」「**润色**」两行用来指定各自优先使用哪个接口;选「按顺序」则按下方列表的先后使用。
- 下方每张卡片是一个接口。点「**添加接口**」新建一张空白卡片;点「**常用服务**」选一家,新建一张已填好名称、Base URL 和模型的卡片,只需再填 API Key。
- 卡片收起时一行显示名称、协议和模型,点一下展开编辑。
- 卡片左边的把手可以拖动调整先后;右边是删除按钮和启用开关。

## 需要填写的字段

| 字段 | 说明 |
| --- | --- |
| 协议 | 卡片展开后的两行:「API Key」一行是「OpenAI 兼容」「Google」,「账号登录」一行是「Grok 账号」「Claude 订阅」「Codex 订阅」。绝大多数服务(含国内服务和本地程序)选 **OpenAI 兼容**;Google Gemini 官方接口与 Vertex AI 选 **Google**;用 Grok 账号登录选 **Grok 账号**;用 Claude Pro / Max 或 ChatGPT 订阅选 **Claude 订阅** / **Codex 订阅**(后三种都不填 Base URL 和 Key,见下文)。 |
| 显示名称 | 自己起的名字,只用于界面显示,例如「DeepSeek」。 |
| 模型 | 服务商规定的模型 ID,在「模型」一行末尾的输入框里填,回车添加(用逗号隔开可一次加几个)。可以添加多个,按排列的先后使用,前一个失败时自动换下一个;点模型旁的叉去掉。 |
| Base URL | 接口地址,写到版本号那一层为止(通常以 `/v1` 结尾)。**不要**带 `/chat/completions` 或 `/models`,Penna 会自动拼上。 |
| API Key | 服务商后台生成的密钥。本地程序通常不需要,留空即可。 |
| 上下文上限(K) | 选填,单位是千 token,例如 `1000`。留空时按模型名自动识别;认不出的模型圆环不显示占比。 |

填写完毕后:

1. 点「**拉取模型**」:向接口请求模型列表,列表中点击即可勾选,勾选的先后就是使用顺序。
2. 点「**测试连接**」:向每个模型发一句话,收到回应即显示「连接正常」。
3. 改动自动保存:输入停下约半秒后写入;选协议、添加或去掉模型立即写入。

#### Claude 订阅与 Codex 订阅

这两种协议调用本机安装好的命令行工具:「Claude 订阅」用 Claude Code(`claude`),「Codex 订阅」用 Codex(`codex`)。先在终端里装好并登录(运行 `claude` 按提示登录;运行 `codex login`),Penna 用的就是这里登录的账号,用量算在你的订阅里。模型名称:Claude 填 `opus`、`sonnet` 或 `haiku`;Codex 填 `default` 用 Codex 的默认模型,也可以填具体的模型名。这两种协议不支持联网搜索。

### Grok 账号登录

协议选「Grok 账号」后,点「登录 Grok」:Penna 显示一个代码并打开 xAI 的确认页,在浏览器里确认即可。之后 token 自动续期,加密保存在本机。账号需要有 SuperGrok 或 X Premium 这类订阅,是否开放 API 权限由 xAI 决定;没有权限时会提示 `这个 Grok 账号没有 API 权限`,此时可以改用 xAI 的 API Key(协议选 OpenAI 兼容,Base URL 填 `https://api.x.ai/v1`)。

### 联网搜索

页面顶部「联网搜索」一行选「不联网」「自动」或指定接口。Agent 需要查资料时,搜索交给所选接口自带的搜索工具完成,所以写回复的模型本身不必支持联网,例如 DeepSeek 写回复、Gemini 搜索。支持搜索的接口:Google 协议、Grok 账号,以及 Base URL 为 OpenAI、xAI、智谱、阿里云百炼、OpenRouter 官方地址的 OpenAI 协议接口。

### 地址如何拼接

- Grok 账号:请求固定发往 `https://api.x.ai/v1/responses`,Key 以登录得到的 token 发送。
- Claude 订阅 / Codex 订阅:不发网络请求,每条消息启动一次 `claude -p` / `codex exec`,对话拼成一段文字从标准输入传入。
- OpenAI 协议:对话请求发往 `Base URL + /chat/completions`,模型列表来自 `Base URL + /models`,Key 以 `Authorization: Bearer <Key>` 发送。
- Google 协议:请求发往 `Base URL + /models/<模型>:streamGenerateContent`,Key 以请求头 `x-goog-api-key` 发送。
- Base URL 的主机是 `aiplatform.googleapis.com`(含地区前缀)时视为 Vertex AI,Penna 自动补上 `/publishers/google`。Vertex AI 不提供模型列表,模型名称需手动填写。
- Google 接口分三条线:AI Studio(`generativelanguage.googleapis.com`,API Key)、Vertex Express(`https://aiplatform.googleapis.com/v1`,不带项目,API Key)、Vertex 项目路径(`https://aiplatform.googleapis.com/v1/projects/项目/locations/global`,Key 填 `gcloud auth print-access-token` 给的令牌,`ya29.` 开头,以 Bearer 发送,一小时后过期)。
- 「用量档位」:自动(不传,按标准)/ Standard / Flex / Priority。AI Studio 写进请求体的 `service_tier`;Vertex 项目路径写进请求头 `X-Vertex-AI-LLM-Shared-Request-Type`(Flex 另带 `X-Server-Timeout: 600`),先用已买的预配吞吐量;Vertex Express 不能选。Flex 便宜一半但要排队,Penna 最多等 15 分钟,遇到 429 / 503 时仍用 Flex 退避重试 3 次,不会换成更贵的档位;实际档位和选的不一样时(如 Priority 被降成 Standard)记在「模型日志」里。

## 常见服务的 Base URL

| 服务 | 协议 | Base URL | 备注 |
| --- | --- | --- | --- |
| OpenAI | OpenAI | `https://api.openai.com/v1` | |
| DeepSeek | OpenAI | `https://api.deepseek.com/v1` | 模型如 `deepseek-flash`、`deepseek-v4-pro` |
| 硅基流动 SiliconFlow | OpenAI | `https://api.siliconflow.cn/v1` | |
| OpenRouter | OpenAI | `https://openrouter.ai/api/v1` | 模型名带厂商前缀,如 `vendor/model` |
| 阿里云百炼 | OpenAI | `https://dashscope.aliyuncs.com/compatible-mode/v1` | |
| 月之暗面 Kimi | OpenAI | `https://api.moonshot.cn/v1` | 模型如 `kimi-k3.1-pro` |
| 智谱 GLM | OpenAI | `https://open.bigmodel.cn/api/paas/v4` | 版本层是 `v4`;模型如 `glm-5.2` |
| 火山方舟 | OpenAI | `https://ark.cn-beijing.volces.com/api/v3` | 模型名称可填接入点 ID |
| Google Gemini | Google | `https://generativelanguage.googleapis.com/v1beta` | |
| Google Vertex AI | Google | `https://aiplatform.googleapis.com/v1` | 模型名称手动填写 |
| Ollama(本机) | OpenAI | `http://localhost:11434/v1` | Key 留空 |
| LM Studio(本机) | OpenAI | `http://localhost:1234/v1` | Key 留空 |
| Penna 本地反推 | OpenAI | `http://127.0.0.1:8091/v1` | 在「本地反推 → NL 反推」启动服务后点「加入 API 管理」自动填写,模型名称为 `local` |
| 其他中转或自建服务 | 通常为 OpenAI | 服务商提供的地址,写到 `/v1` | |

以上地址以各服务商当前文档为准。

## 模型的选择

- **Agent 对话**:用于写提示词、改提示词、多轮对话,选择能力较强的对话模型。
- **润色**:可单独指定较快、较便宜的模型。
- **看图**:聊天中发送图片使用 Agent 对话的模型;「本地反推 → LLM 反推」使用在那里选中的模型。两者都需要支持图片输入的模型(多模态 / 视觉模型)。
- 一个接口可以填多个模型,多个接口也可以同时启用:请求按顺序尝试,前一个**还没输出内容就失败**时自动换下一个;已经开始输出后出错则直接报错。

## 常见报错

| 报错 | 原因与处理 |
| --- | --- |
| `Base URL 无效:要以 http:// 或 https:// 开头` | 地址缺少协议头,或有多余字符。 |
| `模型接口返回 404:地址不对,返回的是网页。请检查 Base URL` | Base URL 层级不对:多写或少写了 `/v1`,或误加了 `/chat/completions`。 |
| `模型接口返回 401` / `403` | Key 错误、过期、无权限,或余额不足。到服务商后台核对。 |
| `模型接口返回 404`(非网页) | 模型名称不存在或拼写有误,用「拉取模型」核对。 |
| `模型接口返回 429` | 请求过于频繁或额度用尽,稍后再试或更换模型。 |
| `连不上模型接口` | 网络不通、需要代理,或本地程序没有启动。 |
| `HTTPS 握手失败` | 证书或代理问题;本地程序应使用 `http://` 而不是 `https://`。 |
| `请求发不出去:API Key 或接口地址里有非法字符` | Key 或地址里混入了空格、换行或中文字符,重新粘贴。 |
| `接口返回的不是模型列表` | 该服务不提供模型列表,手动填写模型名称。 |
| `Vertex AI 不能拉取模型,请手动填模型名` | Vertex AI 的正常提示,手动填写即可。 |
| `模型没有返回内容` / `模型没有返回可识别的内容` | 模型不支持当前请求(例如向纯文本模型发送了图片),或接口不兼容流式输出。 |
| `请求被 Google 拦截` / `Google 中止了回复` | Google 的安全策略拦截了内容,调整提示词或改用其他模型。 |
| `模型接口超时` | 网络慢或模型响应慢,稍后再试。 |
| `这个 Grok 账号没有 API 权限,可以改用 API Key` | xAI 没有给这个账号开放 API,升级订阅或改用 API Key。 |
| `Grok 登录已失效,请到设置里重新登录` | 到卡片上退出后重新登录。 |
| `Claude Code 没登录:在终端运行 claude 登录` | 在终端运行 `claude`,按提示登录 Claude 账号。 |
| `Codex 没登录或登录过期:在终端运行 codex login` | 在终端运行 `codex login` 重新登录。 |
| `没找到 claude 命令:先安装 Claude Code 并登录` / `没找到 codex 命令:先安装 Codex 并登录` | 命令行工具没装,或不在 PATH 里。 |

## 核对清单(请 AI 在最后给出)

- [ ] 协议选择正确(OpenAI 兼容 / Google / Grok 账号 / Claude 订阅 / Codex 订阅)
- [ ] Base URL 写到版本层,没有多余路径
- [ ] 模型名称与服务商一致,多个时逐个回车添加
- [ ] API Key 已由用户本人填入 Penna(本地程序留空)
- [ ] 「测试连接」显示「连接正常」
- [ ] 「Agent 对话」「润色」两行选择了希望使用的接口
