# MATLAB ZOS-API 连接规则

默认 **Interactive Extension**。Standalone 仅在用户明确要求、或冒烟测试已通过且需要无 GUI 批处理时使用。

不要使用 Zemax DDE（`zde*` / `DDEInit`）。不要使用非 ZOS-API 的 COM 旧封装。

---

## 1. 发现 OpticStudio

按优先级：

1. 调用方传入的 `zosRoot`（安装目录，含 `ZOS-API\Libraries\ZOSAPI_NetHelper.dll`）。
2. 注册表 `HKEY_CURRENT_USER\Software\Zemax` 值 `ZemaxRoot`（数据目录，其下有 `ZOS-API\Libraries\`）。
3. 常见安装路径，例如 `C:\Program Files\Ansys Zemax OpticStudio 2024 R1.00`。
4. 全部失败则停止，要求用户提供 `--zos-root` / `'zosRoot'`。

```matlab
function netHelper = locateNetHelper(zosRoot)
    if nargin >= 1 && ~isempty(zosRoot)
        cands = {fullfile(zosRoot, 'ZOS-API', 'Libraries', 'ZOSAPI_NetHelper.dll')};
    else
        cands = {};
        try
            zemaxData = winqueryreg('HKEY_CURRENT_USER', 'Software\Zemax', 'ZemaxRoot');
            cands{end+1} = fullfile(char(zemaxData), 'ZOS-API', 'Libraries', 'ZOSAPI_NetHelper.dll');
        catch
        end
        cands{end+1} = 'C:\Program Files\Ansys Zemax OpticStudio 2024 R1.00\ZOS-API\Libraries\ZOSAPI_NetHelper.dll';
        cands{end+1} = 'C:\Program Files\Zemax OpticStudio\ZOS-API\Libraries\ZOSAPI_NetHelper.dll';
    end
    netHelper = '';
    for i = 1:numel(cands)
        if exist(cands{i}, 'file')
            netHelper = cands{i};
            return
        end
    end
    error('ZOSAPI_NetHelper.dll not found. Pass zosRoot explicitly.');
end
```

---

## 2. 加载程序集（必须幂等）

同一 MATLAB 会话重复 `NET.addAssembly` 会失败。用 persistent 守卫：

```matlab
function loadZosAssemblies(netHelper)
    persistent loaded
    if ~isempty(loaded) && loaded
        return
    end
    import System.Reflection.*
    NET.addAssembly(netHelper);
    ok = ZOSAPI_NetHelper.ZOSAPI_Initializer.Initialize();
    % 自定义安装目录时：
    % ok = ZOSAPI_NetHelper.ZOSAPI_Initializer.Initialize(zosInstallDir);
    if ok ~= 1
        error('ZOSAPI_NetHelper failed to initialize OpticStudio.');
    end
    NET.addAssembly(AssemblyName('ZOSAPI_Interfaces'));
    NET.addAssembly(AssemblyName('ZOSAPI'));
    loaded = true;
end
```

---

## 3. Interactive Extension（推荐）

OpticStudio 侧：

1. 打开目标镜头或空系统。
2. `Programming → MATLAB → Interactive Extension`。
3. 可选用官方生成的 `MATLABZOSConnectionN.m` 作连接样板；**设计循环不要写进该文件**。

MATLAB 侧：

```matlab
TheConnection = ZOSAPI.ZOSAPI_Connection();
% instanceId: 0 = 任一可用实例；与 Python Skill v1.3 的 -InstanceId 对齐
TheApplication = TheConnection.ConnectAsExtension(int32(instanceId));
```

校验：

```matlab
if isempty(TheApplication)
    error('ConnectAsExtension failed.');
end
if ~TheApplication.IsValidLicenseForAPI
    error('Connected but IsValidLicenseForAPI is false.');
end
TheSystem = TheApplication.PrimarySystem;
if isempty(TheSystem)
    error('PrimarySystem is null.');
end
```

**结束 Interactive 会话时不要 `CloseApplication()`。** 只关闭分析窗口与 Tools。用户的 OpticStudio 必须保持打开。

连接失败常见原因：

- OpticStudio 未点 Interactive Extension。
- 实例已被别的脚本占用。
- `instanceId` 指向不存在的实例（不要写死 21 这类官方截图数字）。
- 许可证不含 API。

---

## 4. Standalone

```matlab
TheConnection = ZOSAPI.ZOSAPI_Connection();
TheApplication = TheConnection.CreateNewApplication();
```

无 GUI，仍消耗许可证。结束必须：

```matlab
function cleanupStandalone(app)
    if ~isempty(app)
        try
            app.CloseApplication();
        catch
        end
    end
end
```

用 `try/catch` 包住业务函数，`catch` 与正常结束都要清理。参考官方模板：`BeginApplication` + `CleanupConnection`。

若出现 OpticStudio 异常对话框或长时间挂起：停止重试 Standalone，改测 Interactive Extension。

---

## 5. 位数与许可证

- 64 位 MATLAB 连 32 位 OpticStudio（或相反）会在加载类型时报 `Unable to load one or more of the requested types`。唯一修复：两边位数一致。
- `IsValidLicenseForAPI == false`：连接对象不可用于设计循环。
- `TheApplication.LicenseStatus`、`TheApplication.Mode` 写入冒烟日志。
- 需要英文 UI/文本分析时：`TheApplication.Preferences.General.Language = ZOSAPI.Preferences.LanguageType.English;`（便于解析导出文本）。

---

## 6. 冒烟测试必须打印的内容

```
Connected: yes|no
Mode: extension|standalone
InstanceId: <n>
IsValidLicenseForAPI: true|false
LicenseStatus: <enum/string>
PrimarySystem: ok|null
ZemaxDirectory: <path>
```

`Connected: yes` 的充要条件：应用非空 **且** 许可证有效 **且** `PrimarySystem` 非空。

---

## 7. 连接函数签名（代理实现时必须遵守）

```matlab
function [app, sys] = connectZemax(opts)
% opts.mode        'extension' (default) | 'standalone'
% opts.instanceId  default 0
% opts.zosRoot     optional install or data path
```

把 `app` 保存在调用方，直到设计循环结束。不要在子函数里让唯一句柄离开作用域后被清掉却仍继续用 `sys`。

Interactive：循环结束返回，不关应用。  
Standalone：`onCleanup(@() cleanupStandalone(app))` 保证异常也能关。
