# 模型配置

```yaml
allowed_models:
  - gpt-5.6-luna
  - claude-haiku
  - deepseek-v4.1-flash
default_model: auto
reasoning_preference: medium
```

## 选择规则

- 候选列表非空，可用宿主精确 ID。单项只选该模型；固定默认须属于列表，不可用时不替换。配置错误直接报告。
- 本轮模型指定优先，可限定角色；推理偏好按「角色指定 → 本轮通用指定 → 配置 → 缺省 `medium`」取值，配置值须为非空字符串。临时覆盖不修改长期默认。
- 从当前宿主声明、派发工具及 schema 核对精确 ID、能力和推理参数；主会话支持不代表子 Agent 可用。只读取必要非敏感信息，不主动付费探测或改宿主配置。
- `auto` 先满足工具、输入、上下文需求及任务实际需要的判断能力，再比较速度和成本。判断能力结合方案已明确的规则、执行中仍需作出的判断及验收要求评估；条件相当时沿用有效默认，其次按列表顺序。
- 推理档位按接口解析，映射须有证据；不支持调节则省略并说明。参数未解析或用户明确档位无法满足时，阻塞受影响角色。
- 每次调用复核；方案记录候选范围、各角色精确 ID、实际参数、理由、限制、证据与授权的失败后候选规则。无派发能力时按入口说明交接手动会话。

ID 线索：Luna 使用接口暴露的 `gpt-5.6-luna`；Haiku 核对宿主 `haiku` 别名或完整 ID；DeepSeek Flash 核对 `deepseek-flash` 映射。别名、版本和参数均以当前接口为准，不自行替换型号。

## 本地记录

确认任务、项目指令和写入授权后，在目标项目 `.crazy-luna/models.local.json` 的顶层 `hosts` 中按宿主保存；无具体任务或整体阻塞时不初始化。

每个宿主条目包含：

- `status`：`ready`、证据不足的 `unknown`、确认不可用的 `unavailable`。
- `allowed_models`、`reasoning_preference`：上述配置，不含临时覆盖。
- `dispatch_supported`：有接口/无接口/未知对应 `true`/`false`/`null`。
- `available_models`：仅含可派发候选，各含 `request_model`、`reasoning_parameters`、`capabilities`、`evidence`。
- `default_model`、`reasoning_parameters`、`selection_reason`：长期默认精确 ID、实际参数及理由。
- `evidence`、`checked_at`、`runtime_model`：来源、检查时间、实际回报型号；未回报型号为 `null`。

固定默认或长期参数不可用、无候选交集或无接口时记 `unavailable`；证据不足记 `unknown`。这两种状态将默认及实际参数置 `null`，保留原因；旧选择可记 `last_selection`，仅主会话模型可记 `host_models`。临时覆盖失败不影响有效长期默认。

更新前读取旧记录，保留其他宿主和未知字段；内容无变化不重写。JSON 或记录结构损坏时停止保存，不覆盖或另建旁路文件。使用现有工具安全写入；失败时注明未保存，继续用本轮结果规划。将 `models.local.json` 补入 `.crazy-luna/.gitignore`，保留原内容；本地记录不随包发布。

## 宿主与校验

保留手动调用策略，遵守派发工具约束（含 `fork_turns`）。运行 `ruby <Skill目录>/scripts/validate.rb` 做静态校验；宿主运行另行实测。
