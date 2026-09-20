; 脚本由 Inno Setup 脚本向导生成。
; 有关创建 Inno Setup 脚本文件的详细信息，请参阅帮助文档！
; 仅供非商业使用

#define MyAppName "Extension"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Your Name"
#define MyAppURL "https://example.com/"

; 安装时顺便从 PATH 里清掉的旧路径（逗号分隔）。留空则不做这件事。
#define MyLegacyPaths ""

; ============================================================================
;  下载源清单地址（改这里就行，后缀随意 —— 安装程序按内容解析，不看扩展名）
;
;  清单格式：方括号节名 [工具|版本标签] + 键 = 值
;      url / url2 / url3   主地址 + 备用地址（失败自动依次重试）
;      size / sha256       可选
;  清单里有多少节，向导下拉框就有多少个版本；加/删版本不用重编译安装包。
;  清单拉不到时会回退到 [Code] 里内置的那份 FallbackManifest。
; ============================================================================
#define MyManifestURL "https://example.com/manifest.ini"

; ============================================================================
;  所需磁盘空间
;
;  载荷全部是运行时下载的，[Files] 里一个条目都没有，所以 Inno 自己算出来的
;  "所需磁盘空间" 只有 4 MB 出头（其实就是卸载程序本身的大小）。
;  这里手工把载荷的占用补上：清单里各包 size 之和 × 2
;  （解压后实测约为压缩包的 1.92 倍，取 2 留点余量）。
;  ⚠ 清单里增删版本后这个数字要重算，生成清单的脚本会一起更新它。
; ============================================================================
#define MyPackBytes 1095494248

[Setup]
; 注意：AppId 的值唯一标识此应用程序。不要在其他应用程序的安装程序中使用相同的 AppId 值。
; (若要生成新的 GUID，请在 IDE 中单击 "工具|生成 GUID"。)
AppId={{60E790EA-91C3-4004-B1E8-C41186BAA668}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName=D:\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=dist
OutputBaseFilename=Extension-Online
; 安装包图标：把 .ico 放到本脚本同目录、改名 app.ico，再取消下面这行的注释。
; 注释掉的话用 Inno Setup 自带默认图标，编译一样能过。
; SetupIconFile=app.ico
ExtraDiskSpaceRequired={#MyPackBytes}
SolidCompression=yes
; ⚠ 这一行不能删！本机 Inno 的默认安装壳 Setup.e32 的下载功能是坏的
;   （会报 "Error adding header: (87)"），带 dark/windows11 的样式才会改用
;   正常的 SetupCustomStyle.e32。去掉样式 = 在线下载整个失效。
WizardStyle=modern dark windows11
; 安装/卸载结束后通知资源管理器重新读取环境变量
ChangesEnvironment=yes
; 解压下载的 .zip 需要 full（默认的 basic 只支持 .7z）
ArchiveExtraction=full

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"
Name: "english"; MessagesFile: "compiler:Languages\English.isl"

[Tasks]
; 全局的"配置环境变量"开关已取消：它会整页隐藏下面的工具选择页，导致没法选版本。
; 环境变量现在由【每个工具自己的下拉框】决定：
;   勾选框打勾          = 安装这个工具
;   下拉框选具体版本    = 安装，并写入该工具的环境变量（在 {app}\bin 生成转发脚本）
;   下拉框选"不设置变量" = 只安装文件，完全不碰环境变量
;   勾选框不打勾        = 这个工具不安装

[Files]
; 工具数据全部由 [Code] 按清单在运行时下载，这里不需要任何条目。
; 唯一会复制进去的是同目录下的说明文件（可选）。

[Icons]
Name: "{group}\{cm:ProgramOnTheWeb,{#MyAppName}}"; Filename: "{#MyAppURL}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

[UninstallDelete]
; 1) bin 目录和里面的转发脚本（java.cmd 等）是安装时由 [Code] 生成的，不在卸载器的文件清单里，
;    不显式删掉的话会残留，还会连带导致安装目录也删不掉。
Type: filesandordirs; Name: "{app}\bin"
; 2) 下面四个目录是运行时下载解压出来的，卸载器不登记，显式删一遍做保险。
Type: filesandordirs; Name: "{app}\java"
Type: filesandordirs; Name: "{app}\maven"
Type: filesandordirs; Name: "{app}\node"
Type: filesandordirs; Name: "{app}\php"
Type: filesandordirs; Name: "{app}\go"
Type: filesandordirs; Name: "{app}\python"
Type: filesandordirs; Name: "{app}\gradle"
; 3) 上面删完后安装目录可能是空的，但卸载器不一定认得它，显式补一刀
Type: dirifempty; Name: "{app}"

[Code]
// ===================== 清单驱动的在线安装 =====================
// 流程：
//   1. 向导初始化时拉取清单（拉不到就用内置 FallbackManifest）
//   2. 按清单里的节生成下拉框 —— 清单有多少节就有多少个可选版本
//   3. 点“安装”后，只下载向导里选中的那些包（url 失败自动换 url2 / url3）
//   4. 解压到 {app}\<子目录>\.in-<版本> 暂存，再改名成规范的 jdk21 / node24 …
//   5. 在 {app}\bin 生成转发脚本，PATH 只加这一条，并写入 *_HOME 变量
//
// 为什么用转发脚本而不是符号链接：java.exe / php.exe 按“自己所在目录”找
// jvm.dll / php8.dll，换目录就报错；实测 symlink/junction 都失败，转发脚本可行。
// ========================================================

const
  ManifestUrl  = '{#MyManifestURL}';
  ManifestBase = 'version-list.dat';   // 下到 {tmp} 用的文件名，后缀随意

  // CA 根证书包。PHP 官方 Windows 包【不附带】CA 证书，不配的话所有 https
  // 请求都会失败（curl 报 "unable to get local issuer certificate"，
  // file_get_contents 直接返回 false）——Composer 之类必然踩到。
  CaUrl = 'https://curl.se/ca/cacert.pem';

  // 官方 pip 引导脚本。清单里的 Python 是 embeddable 版，它按设计不带 pip。
  PipUrl = 'https://bootstrap.pypa.io/get-pip.py';

  EnvChangeMsg   = $001A;  // WM_SETTINGCHANGE
  EnvChangeFlags = $0002;  // SMTO_ABORTIFHUNG
  EnvBroadcastTo = $FFFF;  // HWND_BROADCAST

  StagePrefix  = '.in-';

  // 下拉框第 0 项：表示“这个工具不写环境变量”。
  // 和勾选框是两个维度：
  //   勾选框  = 装不装这个工具（文件）
  //   本选项  = 装（用清单里的默认版本），但不写 *_HOME、不加 PATH、不生成转发脚本
  NoChoiceText = '（不设置变量）';

  // 卸载时要检查/清理的 HOME 类变量名
  HomeVarNames = 'JAVA_HOME;MAVEN_HOME;M2_HOME;NODE_HOME;PHP_HOME;PHPRC;' +
                 'GOROOT;GOPATH;PYTHON_HOME;PYTHONHOME;GRADLE_HOME';

  // 工具表（结构性配置，编译进安装包）：
  //   展示名|环境变量名|子目录|放命令的子目录|要生成转发脚本的扩展名|默认版本
  // 说明：Python 故意用 PYTHON_HOME 而不是 PYTHONHOME —— 后者会覆盖 venv 的
  //       pyvenv.cfg，导致虚拟环境失效，是个常见坑。
  ToolSpec = 'Java|JAVA_HOME|java|bin|.exe|jdk21;' +
             'Maven|MAVEN_HOME|maven|bin|.cmd|maven-3.9.16;' +
             'Node|NODE_HOME|node||.exe,.cmd|node24;' +
             'PHP|PHP_HOME|php||.exe|PHP85;' +
             'Go|GOROOT|go|bin|.exe|Go1.27.1;' +
             'Python|PYTHON_HOME|python||.exe|Python3.14;' +
             'Gradle|GRADLE_HOME|gradle|bin|.bat|Gradle9.7.1';

  // 兜底清单：上面那个 URL 拉不到时用这份（格式与外部清单完全一致）。
  // 这份是线上清单的完整快照 —— 7 个工具全都在，清单服务器挂了也能正常装。
  FallbackManifest =
    '[meta]' + #13#10 +
    'default_Java = jdk25' + #13#10 +
    'default_Maven = maven-3.9.16' + #13#10 +
    'default_Node = node24' + #13#10 +
    'default_PHP = PHP85' + #13#10 +
    'default_Go = Go1.27.1' + #13#10 +
    'default_Python = Python3.14' + #13#10 +
    'default_Gradle = Gradle9.7.1' + #13#10 +
    '[Java|jdk25]' + #13#10 +
    'url = https://mirrors.huaweicloud.com/openjdk/25.0.2/openjdk-25.0.2_windows-x64_bin.zip' + #13#10 +
    'size = 221671696' + #13#10 +
    'sha256 = 74784a0c07258f32d36e9224dd79187c566d831c30d47dc06888d4212087331d' + #13#10 +
    '[Maven|maven-3.9.16]' + #13#10 +
    'url = https://mirrors.huaweicloud.com/apache/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.zip' + #13#10 +
    'size = 9395475' + #13#10 +
    'sha256 = 5af3b743dd8b876b5c45da33b676251e5f1687712644abb4ee519ca56e1d89ce' + #13#10 +
    '[Node|node24]' + #13#10 +
    'url = https://mirrors.huaweicloud.com/nodejs/v24.21.0/node-v24.21.0-win-x64.zip' + #13#10 +
    'size = 37618919' + #13#10 +
    'sha256 = 158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541' + #13#10 +
    '[PHP|PHP85]' + #13#10 +
    'url = https://downloads.php.net/~windows/releases/archives/php-8.5.10-nts-Win32-vs17-x64.zip' + #13#10 +
    'url2 = https://windows.php.net/downloads/releases/archives/php-8.5.10-nts-Win32-vs17-x64.zip' + #13#10 +
    'size = 36023055' + #13#10 +
    'sha256 = 22ec430195984d233eb9e62c637a945bbcda06efca2f392d9d96d62c6acd34f8' + #13#10 +
    '[Go|Go1.27.1]' + #13#10 +
    'url = https://mirrors.nju.edu.cn/golang/go1.27.1.windows-amd64.zip' + #13#10 +
    'url2 = https://golang.google.cn/dl/go1.27.1.windows-amd64.zip' + #13#10 +
    'size = 78931360' + #13#10 +
    'sha256 = a3911b5e0e1b1053f25ed0675f4c1c6aad1e2bfcf253df2b9be4caabd2edd95d' + #13#10 +
    '[Python|Python3.14]' + #13#10 +
    'url = https://mirrors.huaweicloud.com/python/3.14.7/python-3.14.7-embed-amd64.zip' + #13#10 +
    'size = 12673227' + #13#10 +
    'sha256 = d297e5ff019966817ad8502465176139f2d3d840fa4ed84b13bed399a6ab1f15' + #13#10 +
    '[Gradle|Gradle9.7.1]' + #13#10 +
    'url = https://mirrors.huaweicloud.com/gradle/gradle-9.7.1-bin.zip' + #13#10 +
    'size = 151433392' + #13#10 +
    'sha256 = acd53f1edaf02f1a8ff99879f8a34b302661a057d9b063ae9e35b552f804d20a' + #13#10;

  LegacyPaths = '{#MyLegacyPaths}';

var
  EnvPage: TWizardPage;
  ToolCheck: array[0..7] of TNewCheckBox;
  ToolCombo: array[0..7] of TNewComboBox;
  ToolCount: Integer;
  ToolName: array[0..7] of String;
  ToolVar:  array[0..7] of String;
  ToolSub:  array[0..7] of String;
  ToolBin:  array[0..7] of String;
  ToolExt:  array[0..7] of String;
  ToolDef:  array[0..7] of String;
  ToolDefPick: array[0..7] of String;  // 默认版本（选不设置变量时用它装文件）

  ManifestPath: String;
  VerCount: Integer;
  VerTool: array[0..255] of String;
  VerName: array[0..255] of String;
  VerU1:   array[0..255] of String;
  VerU2:   array[0..255] of String;
  VerU3:   array[0..255] of String;
  VerSize: array[0..255] of String;   // 清单的 size 字段（包大小，字节）
  VerSha:  array[0..255] of String;   // 清单的 sha256 字段（有就下载后校验）

  DownloadPage: TDownloadWizardPage;
  CapacityLabel: TNewStaticText;   // 选择页底部的"容量估计"实时提示

function SendMessageTimeout(hWnd: Integer; Msg: Integer; wParam: Integer; lParam: String;
  fuFlags: Integer; uTimeout: Integer; var lpdwResult: Integer): Integer;
  external 'SendMessageTimeoutW@user32.dll stdcall';

function SysEnvSubKey(): String;
begin
  Result := 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
end;

function UserEnvSubKey(): String;
begin
  Result := 'Environment';
end;

function TakeField(var S: String): String;
var P: Integer;
begin
  P := Pos('|', S);
  if P > 0 then begin Result := Trim(Copy(S, 1, P - 1)); Delete(S, 1, P); end
  else begin Result := Trim(S); S := ''; end;
end;

function TakeEntry(var S: String): String;
var P: Integer;
begin
  P := Pos(';', S);
  if P > 0 then begin Result := Copy(S, 1, P - 1); Delete(S, 1, P); end
  else begin Result := S; S := ''; end;
end;

procedure ParseToolSpec();
var Rest, One: String;
begin
  ToolCount := 0;
  Rest := ToolSpec;
  while (Rest <> '') and (ToolCount <= 7) do
  begin
    One := TakeEntry(Rest);
    if Trim(One) <> '' then
    begin
      ToolName[ToolCount] := TakeField(One);
      ToolVar[ToolCount]  := TakeField(One);
      ToolSub[ToolCount]  := TakeField(One);
      ToolBin[ToolCount]  := TakeField(One);
      ToolExt[ToolCount]  := TakeField(One);
      ToolDef[ToolCount]  := TakeField(One);
      ToolCount := ToolCount + 1;
    end;
  end;
end;

function ToolIndexOf(const Name: String): Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to ToolCount - 1 do
    if ToolName[I] = Name then begin Result := I; Exit; end;
end;

// 该工具当前要装的版本；空串 = 不装这个工具（勾选框没打勾）
// 这个工具要【安装】的版本：勾选框没勾 = 不装；选了"不设置变量" = 用清单默认版本装文件
function InstallVer(I: Integer): String;
begin
  Result := '';
  if (I < 0) or (I > ToolCount - 1) then Exit;
  if (ToolCheck[I] <> nil) and (not ToolCheck[I].Checked) then Exit;
  if (ToolCombo[I] = nil) or (ToolCombo[I].Items.Count = 0) or (ToolCombo[I].ItemIndex < 0) then Exit;

  if ToolCombo[I].Items[ToolCombo[I].ItemIndex] = NoChoiceText then
    Result := ToolDefPick[I]      // 只装文件，不配环境变量
  else
    Result := ToolCombo[I].Items[ToolCombo[I].ItemIndex];
end;

// 这个工具要不要【写环境变量】：勾了勾选框、并且下拉框选的是具体版本
function EnvEnabled(I: Integer): Boolean;
begin
  Result := False;
  if (I < 0) or (I > ToolCount - 1) then Exit;
  if (ToolCheck[I] = nil) or (not ToolCheck[I].Checked) then Exit;
  if (ToolCombo[I] = nil) or (ToolCombo[I].Items.Count = 0) or (ToolCombo[I].ItemIndex < 0) then Exit;
  Result := ToolCombo[I].Items[ToolCombo[I].ItemIndex] <> NoChoiceText;
end;

// ============================================================================
//  容量估计
//
//  载荷是边下边解压的，占用分两处：
//    安装目录  —— 解压后的体积，约等于压缩包的 2 倍（实测 1.92 倍）
//    临时目录  —— 下载中的压缩包本体（解压完就删）
//  所以这里按当前勾选/下拉框实时算，勾掉工具数字马上就降下来。
// ============================================================================
procedure UpdateCapacity();
var
  I, TI: Integer;
  Pick, Unknown, Warn, Drive: String;
  PackBytes, InstBytes, FreeBytes, TotalBytes: Int64;
begin
  if CapacityLabel = nil then Exit;

  PackBytes := 0;
  Unknown := '';
  for TI := 0 to ToolCount - 1 do
  begin
    Pick := InstallVer(TI);
    if Pick = '' then continue;              // 没勾选 = 不占地方
    for I := 0 to VerCount - 1 do
      if (VerTool[I] = ToolName[TI]) and (VerName[I] = Pick) then
      begin
        if VerSize[I] = '' then Unknown := '（部分包大小未知）'
        else PackBytes := PackBytes + StrToInt64Def(VerSize[I], 0);
      end;
  end;

  InstBytes := PackBytes * 2;                // 解压后约 2 倍

  // 安装目录所在盘够不够
  Warn := '';
  Drive := ExtractFileDrive(WizardDirValue());
  if (InstBytes > 0) and GetSpaceOnDisk64(WizardDirValue(), FreeBytes, TotalBytes) then
    if FreeBytes < InstBytes then
      Warn := '　⚠ ' + Drive + ' 只剩 ' + IntToStr(FreeBytes div 1048576) + ' MB，不够';

  CapacityLabel.Caption :=
    '容量估计：安装目录约 ' + IntToStr(InstBytes div 1048576) + ' MB' +
    '，另需下载缓存约 ' + IntToStr(PackBytes div 1048576) + ' MB（临时目录）' +
    Unknown + Warn;
end;

// 勾选框被点：同步启用/禁用右边的版本下拉框，并刷新容量估计
procedure ToolCheckClick(Sender: TObject);
var I: Integer;
begin
  for I := 0 to ToolCount - 1 do
    if ToolCheck[I] = Sender then
      ToolCombo[I].Enabled := ToolCheck[I].Checked and (ToolCombo[I].Items.Count > 1);
  UpdateCapacity();
end;

// 下拉框换版本：不同版本大小不一样，容量估计要跟着变
procedure ToolComboChange(Sender: TObject);
begin
  UpdateCapacity();
end;

// ============ 清单：拉取 + 解析 ============
function FetchManifest(): Boolean;
var S: String;
begin
  Result := True;
  ManifestPath := ExpandConstant('{tmp}\' + ManifestBase);
  try
    DownloadTemporaryFile(ManifestUrl, ManifestBase, '', nil);
    Log('清单：已从 ' + ManifestUrl + ' 拉取');
  except
    Result := False;
    Log('清单：拉取失败（' + GetExceptionMessage + '），改用内置兜底清单');
    S := FallbackManifest;
    if not SaveStringToFile(ManifestPath, S, False) then
      Log('清单：内置兜底清单写入失败！');
  end;
end;

// 逐行找 [工具|版本] 节名，再用 GetIniString 取该节的值
procedure ParseManifest();
var
  Lines: TArrayOfString;
  I, P, TI: Integer;
  Line, Sec, T, V: String;
begin
  VerCount := 0;
  if not LoadStringsFromFile(ManifestPath, Lines) then
  begin
    Log('清单：读取失败 ' + ManifestPath);
    Exit;
  end;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[I]);
    if (Length(Line) >= 3) and (Line[1] = '[') and (Line[Length(Line)] = ']') then
    begin
      Sec := Copy(Line, 2, Length(Line) - 2);
      P := Pos('|', Sec);
      if P > 0 then
      begin
        T := Trim(Copy(Sec, 1, P - 1));
        V := Trim(Copy(Sec, P + 1, Length(Sec) - P));
        TI := ToolIndexOf(T);
        if (TI < 0) then
          Log('清单：忽略未知工具 ' + T)
        else if (V = '') then
          Log('清单：忽略空版本名 ' + Sec)
        else if VerCount > 255 then
          Log('清单：版本过多，已截断')
        else
        begin
          VerTool[VerCount] := T;
          VerName[VerCount] := V;
          VerU1[VerCount] := GetIniString(Sec, 'url',  '', ManifestPath);
          VerU2[VerCount] := GetIniString(Sec, 'url2', '', ManifestPath);
          VerU3[VerCount] := GetIniString(Sec, 'url3', '', ManifestPath);
          VerSize[VerCount] := GetIniString(Sec, 'size', '', ManifestPath);
          VerSha[VerCount] := GetIniString(Sec, 'sha256', '', ManifestPath);
          if VerU1[VerCount] = '' then
            Log('清单：' + Sec + ' 没有 url，跳过');
          VerCount := VerCount + 1;
        end;
      end;
    end;
  end;
  Log('清单：解析到 ' + IntToStr(VerCount) + ' 个版本');
end;

// 每个包在 {tmp} 里用的文件名（各工具/版本唯一）
function VerBaseName(I: Integer): String;
begin
  Result := VerTool[I] + '_' + VerName[I] + '.zip';
end;

// ============ 向导页：按清单生成下拉框 ============
procedure InitializeWizard();
var I, J: Integer; Def: String;
begin
  ParseToolSpec();

  FetchManifest();
  ParseManifest();

  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing),
    SetupMessage(msgPreparingDesc), nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;

  EnvPage := CreateCustomPage(wpSelectTasks, '选择要安装的工具与版本',
    '勾选框 = 是否安装该工具；下拉框选一个具体版本 = 安装并写入环境变量；选“' +
    NoChoiceText + '” = 只安装文件，不写任何环境变量。');

  for I := 0 to ToolCount - 1 do
  begin
    // 勾选开关：默认全勾；取消勾选 = 不装这个工具
    ToolCheck[I] := TNewCheckBox.Create(EnvPage);
    ToolCheck[I].Parent := EnvPage.Surface;
    ToolCheck[I].Left := 0;
    ToolCheck[I].Top := ScaleY(I * 34);
    ToolCheck[I].Width := ScaleX(145);
    ToolCheck[I].Caption := ToolName[I] + '  (' + ToolVar[I] + ')';
    ToolCheck[I].Checked := True;
    ToolCheck[I].OnClick := @ToolCheckClick;

    ToolCombo[I] := TNewComboBox.Create(EnvPage);
    ToolCombo[I].Parent := EnvPage.Surface;
    ToolCombo[I].Left := ScaleX(150);
    ToolCombo[I].Top := ScaleY(I * 34);
    ToolCombo[I].Width := ScaleX(230);
    ToolCombo[I].Style := csDropDownList;
    ToolCombo[I].OnChange := @ToolComboChange;
    // 第 0 项 = 不设置变量；具体版本从第 1 项开始
    ToolCombo[I].Items.Add(NoChoiceText);

    // 清单里属于这个工具的版本，按清单顺序进下拉框
    for J := 0 to VerCount - 1 do
      if (VerTool[J] = ToolName[I]) and (VerU1[J] <> '') then
        ToolCombo[I].Items.Add(VerName[J]);

    // 默认选中项：优先读清单 [meta] 里的 default_<工具名>，
    // 没有就用工具表里编译的默认值；两者都不在下拉框里就退回第一个可用版本
    Def := GetIniString('meta', 'default_' + ToolName[I], '', ManifestPath);
    if Def = '' then
      Def := GetIniString('meta', 'default_' + LowerCase(ToolName[I]), '', ManifestPath);
    if Def = '' then
      Def := ToolDef[I];

    ToolCombo[I].ItemIndex := ToolCombo[I].Items.IndexOf(Def);
    if ToolCombo[I].ItemIndex < 1 then
    begin
      if ToolCombo[I].Items.Count > 1 then
        ToolCombo[I].ItemIndex := 1     // 退回第一个真实版本（第 0 项是"不设置变量"）
      else
        ToolCombo[I].ItemIndex := 0;
    end;

    // 关键：ToolDefPick 必须落成清单里【真实存在】的版本名。
    // 否则选了"不设置变量"时会拿编译期默认值（如 jdk21）去装一个清单里没有的版本，
    // 下载环节匹配不到就静默跳过 —— 用户看到的是"勾了却没装上"。
    if ToolCombo[I].ItemIndex >= 1 then
      ToolDefPick[I] := ToolCombo[I].Items[ToolCombo[I].ItemIndex]
    else
      ToolDefPick[I] := Def;

    // 清单里这个工具一个版本都没有 → 没法装，勾选框禁用并取消勾选
    if ToolCombo[I].Items.Count <= 1 then   // 只剩"不设置变量"一项 = 清单里没有这个工具的版本
    begin
      ToolCheck[I].Checked := False;
      ToolCheck[I].Enabled := False;
      ToolCombo[I].Enabled := False;
    end;
  end;

  // 页面底部：按当前选择实时显示要占多少磁盘
  CapacityLabel := TNewStaticText.Create(EnvPage);
  CapacityLabel.Parent := EnvPage.Surface;
  CapacityLabel.Left := 0;
  CapacityLabel.Top := ScaleY(ToolCount * 34 + 8);
  CapacityLabel.Caption := '';
  UpdateCapacity();
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // 这一页永远显示：装不装、装哪个版本、要不要写环境变量，全在这一页上决定。
  Result := False;
end;

// ============ 下载：只下选中的，失败自动换备用地址 ============
function NextButtonClick(CurPageID: Integer): Boolean;
var
  I, TI, Pass: Integer;
  Url, Base: String;
  ErrText: String;
  Pending: array[0..255] of Boolean;
  Any: Boolean;
begin
  Result := True;
  if CurPageID <> wpReady then Exit;

  for I := 0 to VerCount - 1 do
  begin
    TI := ToolIndexOf(VerTool[I]);
    Pending[I] := (VerU1[I] <> '') and (TI >= 0) and (InstallVer(TI) = VerName[I]);
  end;

  for Pass := 1 to 3 do
  begin
    Any := False;
    DownloadPage.Clear;
    for I := 0 to VerCount - 1 do
    begin
      if not Pending[I] then continue;
      Base := ExpandConstant('{tmp}\' + VerBaseName(I));
      if FileExists(Base) then begin Pending[I] := False; continue; end;   // 上一轮已下好
      case Pass of
        1: Url := VerU1[I];
        2: Url := VerU2[I];
      else Url := VerU3[I];
      end;
      if Url = '' then continue;
      // 清单里给了 sha256 就交给下载器校验（不匹配会抛异常并触发换备用地址）
      DownloadPage.Add(Url, VerBaseName(I), VerSha[I]);
      if VerSha[I] <> '' then
        Log('下载：' + VerName[I] + ' 将校验 sha256');
      Any := True;
    end;

    if not Any then Break;   // 没有可试的了

    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if DownloadPage.AbortedByUser then
        begin
          Log('下载：用户取消');
          Result := False;
        end
        else
        begin
          ErrText := Format('%s: %s', [DownloadPage.LastBaseNameOrUrl, GetExceptionMessage]);
          Log('下载失败（第 ' + IntToStr(Pass) + ' 轮）：' + ErrText);
        end;
      end;
    finally
      DownloadPage.Hide;
    end;

    if not Result then Exit;

    // 检查这一轮之后还有没有没下好的
    Any := False;
    for I := 0 to VerCount - 1 do
      if Pending[I] and (not FileExists(ExpandConstant('{tmp}\' + VerBaseName(I)))) then
        Any := True;
    if not Any then Break;

    if Pass = 3 then
    begin
      MsgBox('以下文件三组地址都下载失败，安装无法继续：' + #13#10 +
             DownloadPage.LastBaseNameOrUrl, mbCriticalError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

// ============ 解压 + 就位 ============
function ExtractSelected(): Boolean;
var I, TI: Integer; Zip, Stage: String;
begin
  Result := True;
  for I := 0 to VerCount - 1 do
  begin
    TI := ToolIndexOf(VerTool[I]);
    if (TI < 0) or (InstallVer(TI) <> VerName[I]) then continue;

    Zip := ExpandConstant('{tmp}\' + VerBaseName(I));
    if not FileExists(Zip) then
    begin
      Log('解压：找不到 ' + Zip);
      continue;
    end;

    Stage := ExpandConstant('{app}\' + ToolSub[TI] + '\' + StagePrefix + VerName[I]);
    ForceDirectories(Stage);
    try
      ExtractArchive(Zip, Stage, '', True, nil);
      Log('解压：' + VerBaseName(I) + '  ->  ' + Stage);
    except
      Log('解压失败：' + VerBaseName(I) + ' : ' + GetExceptionMessage);
      Result := False;
    end;
  end;
end;

// 把暂存目录改名成规范目录名
procedure PromoteStaged();
var
  I, SubDirs, Files: Integer;
  Stage, Final, Child: String;
  FindRec: TFindRec;
  Pick: String;
begin
  for I := 0 to ToolCount - 1 do
  begin
    Pick := InstallVer(I);
    if Pick = '' then continue;

    Stage := ExpandConstant('{app}\' + ToolSub[I] + '\' + StagePrefix + Pick);
    Final := ExpandConstant('{app}\' + ToolSub[I] + '\' + Pick);
    if not DirExists(Stage) then continue;

    SubDirs := 0; Files := 0; Child := '';
    if FindFirst(Stage + '\*', FindRec) then
    begin
      repeat
        // 注意：Inno 的 FindFirst 会把 . 和 .. 也列出来，必须排掉，
        // 否则子目录数会算成 3，判断就走到错误分支（会多套一层目录）
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          begin SubDirs := SubDirs + 1; Child := FindRec.Name; end
          else Files := Files + 1;
        end;
      until not FindNext(FindRec);
      FindClose(FindRec);
    end;

    if (SubDirs = 1) and (Files = 0) then
    begin
      if RenameFile(Stage + '\' + Child, Final) then
      begin RemoveDir(Stage); Log('就位：' + Pick + '  <-  ' + Child); end
      else Log('就位失败（改名）: ' + Stage + '\' + Child + ' -> ' + Final);
    end
    else
    begin
      if RenameFile(Stage, Final) then Log('就位：' + Pick)
      else Log('就位失败（改名）: ' + Stage + ' -> ' + Final);
    end;
  end;
end;

// PHP 官方压缩包里只有 php.ini-development / php.ini-production 两个模板，
// 没有 php.ini，而且模板里所有 extension= 都是注释掉的 ——
// 直接复制过去会得到一个不加载任何扩展的“裸”PHP。
// 所以这里：选模板 → 把随包自带的扩展行全部放开 → 写成 php.ini。
// 已经存在 php.ini 就完全不动（保留你自己的改动）。
// ext\ 目录里有没有这个扩展对应的 DLL。
// Windows 官方包的 DLL 名是 php_<扩展名>.dll（模板里写的是 ;extension=curl 这种短名）。
function ExtDllExists(const ExtDir, Name: String): Boolean;
var N: String;
begin
  Result := False;
  N := LowerCase(Trim(Name));
  if N = '' then Exit;
  if Copy(N, Length(N) - 3, 4) = '.dll' then
    Result := FileExists(ExtDir + '\' + N)
  else if Copy(N, 1, 4) = 'php_' then
    Result := FileExists(ExtDir + '\' + N + '.dll')
  else
    Result := FileExists(ExtDir + '\php_' + N + '.dll');
end;

// 用装好的 php.exe 逐个扩展实测，把"有问题"的扩展从 php.ini 里剔除。
// 判据：-r "" 这种空程序成功运行时本应【毫无输出】，所以 stdout+stderr 里
// 只要有内容就说明这个扩展不干净。一条判据同时覆盖两类坑：
//   1) DLL 在包里、但它依赖的第三方库不在（pdo_firebird 需要 fbclient.dll）
//      —— PHP 会往 stdout 打 "Unable to load dynamic library" 警告；
//   2) DLL 能加载、但库自己往 stderr 喷噪音（snmp 找不着 MIB 数据文件，
//      每次启动都刷十几行 "Cannot find module ..."）。
// 不用硬编码黑名单，PHP 换版本也不会失效。
// 返回被剔除的个数；探测没跑起来就返回 0 —— 宁可多放开几个，也不能少放开。
function ProbePhpExtensions(const PhpExe, ExtDir: String; var Lines: TArrayOfString;
  N: Integer): Integer;
var
  I, J, P, Rc: Integer;
  CmdFile, OutFile, BadFile, Rest, Name, Script, Line: String;
  BadLines: TArrayOfString;
begin
  Result := 0;
  CmdFile := ExpandConstant('{tmp}\php-probe.cmd');
  OutFile := ExpandConstant('{tmp}\php-probe.out');
  BadFile := ExpandConstant('{tmp}\php-probe.bad');

  // 收集候选扩展名（此时它们都已被放开）
  Rest := '';
  for I := 0 to N - 1 do
  begin
    Line := Trim(Lines[I]);
    if Copy(LowerCase(Line), 1, 10) = 'extension=' then
      Rest := Rest + Trim(Copy(Line, 11, Length(Line) - 10)) + #13#10;
  end;
  if Rest = '' then Exit;

  // 生成一个批处理：每个扩展单独起一次 php（-n 不带 ini，-r "" 空程序），
  // 输出文件非空就把它的名字记进 bad 列表。
  Script := '@echo off' + #13#10 + 'del "' + BadFile + '" 2>nul' + #13#10;
  while Rest <> '' do
  begin
    P := Pos(#13#10, Rest);
    if P > 0 then begin Name := Copy(Rest, 1, P - 1); Delete(Rest, 1, P + 1); end
    else begin Name := Rest; Rest := ''; end;
    Name := Trim(Name);
    if Name = '' then Continue;
    Script := Script +
      '"' + PhpExe + '" -n -d extension_dir="' + ExtDir + '" -d extension=' + Name +
      ' -r "" > "' + OutFile + '" 2>&1' + #13#10 +
      'for %%A in ("' + OutFile + '") do if %%~zA GTR 0 echo ' + Name +
      '>>"' + BadFile + '"' + #13#10;
  end;

  if not SaveStringToFile(CmdFile, Script, False) then Exit;
  if not Exec(CmdFile, '', '', SW_HIDE, ewWaitUntilTerminated, Rc) then Exit;
  if not FileExists(BadFile) then Exit;
  if not LoadStringsFromFile(BadFile, BadLines) then Exit;

  for J := 0 to GetArrayLength(BadLines) - 1 do
  begin
    Name := LowerCase(Trim(BadLines[J]));
    if Name = '' then Continue;
    for I := 0 to N - 1 do
    begin
      Line := Trim(Lines[I]);
      if Copy(LowerCase(Line), 1, 10) = 'extension=' then
        if LowerCase(Trim(Copy(Line, 11, Length(Line) - 10))) = Name then
        begin
          Lines[I] := ';' + Lines[I];
          Result := Result + 1;
          Log('php.ini：剔除有问题的扩展 ' + Name);
        end;
    end;
  end;
end;

// 下 CA 根证书包放进 PHP 目录，并把模板里注释掉的 curl.cainfo / openssl.cafile
// 指到它上面。下载失败不算致命（只是 https 用不了），会记进日志。
// 注：证书包本身没法校验固定 sha256 —— curl.se 会定期更新它，写死就会失效；
//     传输过程由安装程序自己的 TLS 栈校验，安全性由那一层保证。
function SetupPhpCaBundle(const PhpDir: String; var Lines: TArrayOfString;
  N: Integer): Boolean;
var
  I: Integer;
  CaFile, Low: String;
begin
  Result := False;
  CaFile := PhpDir + '\cacert.pem';
  try
    DownloadTemporaryFile(CaUrl, 'cacert.pem', '', nil);
    Result := FileCopy(ExpandConstant('{tmp}\cacert.pem'), CaFile, False);
  except
    Log('CA 证书包下载失败，https 将不可用：' + GetExceptionMessage);
    Result := False;
  end;
  if not Result then Exit;

  for I := 0 to N - 1 do
  begin
    Low := LowerCase(Trim(Lines[I]));
    if Copy(Low, 1, 12) = ';curl.cainfo' then
      Lines[I] := 'curl.cainfo = "' + CaFile + '"'
    else if Copy(Low, 1, 15) = ';openssl.cafile' then
      Lines[I] := 'openssl.cafile = "' + CaFile + '"';
  end;
  Log('CA 证书包就位：' + CaFile + '（curl.cainfo + openssl.cafile 已指向它）');
end;

procedure EnsurePhpIni();
var
  I, J, N, Count, Skipped, Disabled: Integer;
  Dir, Pick, Tpl, Dest, Line, Low, ExtDir, ExtName, PhpExe: String;
  Lines: TArrayOfString;
  DirSet, CaOk: Boolean;
begin
  I := ToolIndexOf('PHP');
  if I < 0 then Exit;
  Pick := InstallVer(I);
  if Pick = '' then Exit;

  Dir := ExpandConstant('{app}\' + ToolSub[I] + '\' + Pick);
  if not DirExists(Dir) then Exit;

  Dest := Dir + '\php.ini';
  if FileExists(Dest) then
  begin
    Log('php.ini 已存在，保持不动：' + Dest);
    Exit;
  end;

  // 优先 development 模板（display_errors 打开，适合开发环境）
  Tpl := Dir + '\php.ini-development';
  if not FileExists(Tpl) then Tpl := Dir + '\php.ini-production';
  if not FileExists(Tpl) then
  begin
    Log('php.ini 模板不存在，跳过：' + Dir);
    Exit;
  end;

  if not LoadStringsFromFile(Tpl, Lines) then Exit;

  // 扩展目录必须是绝对路径：模板里 ;extension_dir 是注释掉的，
  // 不设的话 PHP 会用编译进二进制的默认值（官方 Windows 包是 C:\php\ext），
  // 那个目录不存在，于是所有 extension= 都会加载失败。
  ExtDir := Dir + '\ext';

  Count := 0;
  Skipped := 0;
  DirSet := False;
  N := GetArrayLength(Lines);
  for J := 0 to N - 1 do
  begin
    Line := Trim(Lines[J]);
    Low := LowerCase(Line);
    if Copy(Low, 1, 11) = ';extension=' then
    begin
      // 只放开【ext 目录里真有对应 DLL】的扩展行。
      // 官方 Windows 包有些扩展（例如 pdo_firebird）压根没带 DLL，
      // 放开它们只会让每次 php 启动都打印
      // "Unable to load dynamic library ..." 警告，纯属噪音。
      // （zend_extension 一律不动：opcache/xdebug 的 DLL 不在官方包里）
      ExtName := Trim(Copy(Line, 12, Length(Line) - 11));
      if (ExtName <> '') and ExtDllExists(ExtDir, ExtName) then
      begin
        Lines[J] := Copy(Line, 2, Length(Line) - 1);
        Count := Count + 1;
      end
      else
        Skipped := Skipped + 1;
    end
    else if (not DirSet) and (Copy(Low, 1, 15) = ';extension_dir ') then
    begin
      // 第一条 ;extension_dir 换成绝对路径
      Lines[J] := 'extension_dir = "' + ExtDir + '"';
      DirSet := True;
    end;
  end;

  // 实测一遍：把"标注放开、但实际加载不起来"的扩展重新注释掉
  PhpExe := Dir + '\php.exe';
  Disabled := 0;
  if (Count > 0) and FileExists(PhpExe) then
    Disabled := ProbePhpExtensions(PhpExe, ExtDir, Lines, N);

  // CA 根证书：没有它 PHP 的 https 基本没法用
  CaOk := SetupPhpCaBundle(Dir, Lines, N);

  if SaveStringsToFile(Dest, Lines, False) then
    Log('已生成 php.ini（放开 ' + IntToStr(Count - Disabled) + ' 个扩展；跳过 ' +
        IntToStr(Skipped) + ' 个包里没 DLL 的、实测剔除 ' + IntToStr(Disabled) +
        ' 个有问题的；extension_dir=' + ExtDir + '；CA 包=' +
        IntToStr(Ord(CaOk)) + '）：' + Dest)
  else
    Log('php.ini 写入失败：' + Dest);
end;

// ============ 环境变量 ============
function NormalizeEntry(const Value: String): String;
var S: String;
begin
  S := Trim(Value);
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    S := Trim(Copy(S, 2, Length(S) - 2));
  while (Length(S) > 0) and (S[Length(S)] = '\') do Delete(S, Length(S), 1);
  Result := LowerCase(S);
end;

function IsUnderApp(const Value: String): Boolean;
var V, R: String;
begin
  V := NormalizeEntry(Value);
  R := NormalizeEntry(ExpandConstant('{app}'));
  Result := (V = R) or (Copy(V, 1, Length(R) + 1) = R + '\');
end;

function IsUnderLegacy(const Value: String): Boolean;
var V, Rest, One: String;
begin
  Result := False;
  V := NormalizeEntry(Value);
  if (V = '') or (Trim(LegacyPaths) = '') then Exit;
  Rest := LegacyPaths;
  while Rest <> '' do
  begin
    One := Trim(TakeEntry(Rest));
    if One <> '' then
    begin
      One := NormalizeEntry(One);
      if (V = One) or (Copy(V, 1, Length(One) + 1) = One + '\') then begin Result := True; Exit; end;
    end;
  end;
end;

function PathFilterOut(const PathValue: String; RemoveApp, RemoveLegacy: Boolean): String;
var Rest, Part, Acc: String; P: Integer; Drop: Boolean;
begin
  Acc := ''; Rest := PathValue;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P > 0 then begin Part := Trim(Copy(Rest, 1, P - 1)); Delete(Rest, 1, P); end
    else begin Part := Trim(Rest); Rest := ''; end;

    Drop := False;
    if Part <> '' then
    begin
      if RemoveApp and IsUnderApp(Part) then Drop := True;
      if RemoveLegacy and IsUnderLegacy(Part) then Drop := True;
    end;
    if (Part <> '') and (not Drop) then
    begin
      if Acc <> '' then Acc := Acc + ';';
      Acc := Acc + Part;
    end;
  end;
  Result := Acc;
end;

procedure WritePathValue(const Root: Integer; const Sub: String; const PathValue: String);
begin
  if PathValue = '' then RegDeleteValue(Root, Sub, 'Path')
  else RegWriteExpandStringValue(Root, Sub, 'Path', PathValue);
end;

procedure BroadcastEnvironmentChange();
var Dummy: Integer;
begin
  SendMessageTimeout(EnvBroadcastTo, EnvChangeMsg, 0, 'Environment', EnvChangeFlags, 5000, Dummy);
end;

procedure ClearShims();
var FindRec: TFindRec; Dir, Name: String;
begin
  Dir := ExpandConstant('{app}\bin');
  if not DirExists(Dir) then Exit;
  if FindFirst(Dir + '\*.cmd', FindRec) then
  begin
    repeat
      Name := FindRec.Name;
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        if DeleteFile(Dir + '\' + Name) then Log('清除旧转发脚本：' + Name);
    until not FindNext(FindRec);
    FindClose(FindRec);
  end;
end;

function GenerateShims(const Sub, Ver, BinSub, ExtList: String): Integer;
var
  FindRec: TFindRec;
  BinDir, RelDir, Name, Ext, Base, Target, ShimPath, Content: String;
begin
  Result := 0;
  if BinSub = '' then RelDir := Sub + '\' + Ver
  else RelDir := Sub + '\' + Ver + '\' + BinSub;
  BinDir := ExpandConstant('{app}\' + RelDir);
  if not DirExists(BinDir) then begin Log('转发脚本：目录不存在 ' + BinDir); Exit; end;

  ForceDirectories(ExpandConstant('{app}\bin'));
  if FindFirst(BinDir + '\*', FindRec) then
  begin
    repeat
      Name := FindRec.Name;
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
      begin
        Ext := LowerCase(ExtractFileExt(Name));
        if Pos(',' + Ext + ',', ',' + LowerCase(ExtList) + ',') > 0 then
        begin
          Base := Copy(Name, 1, Length(Name) - Length(Ext));
          ShimPath := ExpandConstant('{app}\bin\' + Base + '.cmd');
          if FileExists(ShimPath) then Log('转发脚本：已存在同名，跳过 ' + Base + '.cmd')
          else
          begin
            Target := '%~dp0..\' + RelDir + '\' + Name;
            // .cmd / .bat 都是批处理（Gradle 的启动器就是 gradle.bat），要用 call 才能正确返回
            if (Ext = '.cmd') or (Ext = '.bat') then
              Content := '@echo off' + #13#10 + 'call "' + Target + '" %*' + #13#10
            else
              Content := '@echo off' + #13#10 + '"' + Target + '" %*' + #13#10;
            if SaveStringToFile(ShimPath, Content, False) then
            begin Result := Result + 1; Log('转发脚本：' + Base + '.cmd'); end
            else Log('转发脚本：写入失败 ' + ShimPath);
          end;
        end;
      end;
    until not FindNext(FindRec);
    FindClose(FindRec);
  end;
end;

procedure ApplyEnvironment();
var
  Root, I, Shims: Integer;
  Sub, PathValue, HomePath, CurValue, Name, Rest, Pick: String;
  Configured: Boolean;
begin
  if IsAdminInstallMode() then begin Root := HKLM; Sub := SysEnvSubKey(); end
  else begin Root := HKCU; Sub := UserEnvSubKey(); end;

  PathValue := '';
  RegQueryStringValue(Root, Sub, 'Path', PathValue);
  PathValue := PathFilterOut(PathValue, True, True);

  Rest := HomeVarNames;
  while Rest <> '' do
  begin
    Name := TakeEntry(Rest);
    CurValue := '';
    if RegQueryStringValue(Root, Sub, Name, CurValue) then
      if IsUnderLegacy(CurValue) then
      begin
        Log('清理旧变量 ' + Name + ' = ' + CurValue);
        RegDeleteValue(Root, Sub, Name);
      end;
  end;

  ClearShims();
  Configured := False;
  Shims := 0;
  for I := 0 to ToolCount - 1 do
  begin
    if not EnvEnabled(I) then
    begin
      Log('不写环境变量（下拉框选了“不设置变量”）：' + ToolName[I]);
      continue;
    end;
    Pick := InstallVer(I);
    if Pick = '' then continue;
    HomePath := ExpandConstant('{app}\' + ToolSub[I] + '\' + Pick);
    if not DirExists(HomePath) then begin Log('跳过不存在的目录: ' + HomePath); continue; end;

    RegWriteExpandStringValue(Root, Sub, ToolVar[I], HomePath);
    Log(ToolVar[I] + ' = ' + HomePath);
    Shims := Shims + GenerateShims(ToolSub[I], Pick, ToolBin[I], ToolExt[I]);
    // Python 的 pip/pip3 等命令装在 Scripts 子目录里，额外扫一遍一起生成转发脚本
    if ToolSub[I] = 'python' then
      Shims := Shims + GenerateShims(ToolSub[I], Pick, 'Scripts', '.exe');
    Configured := True;
  end;

  if Configured then
  begin
    if PathValue = '' then PathValue := ExpandConstant('{app}\bin')
    else PathValue := ExpandConstant('{app}\bin') + ';' + PathValue;
    Log('PATH 增加一条: ' + ExpandConstant('{app}\bin') + '（共 ' + IntToStr(Shims) + ' 个转发脚本）');
  end;

  WritePathValue(Root, Sub, PathValue);
  BroadcastEnvironmentChange();
end;

procedure RemoveHiveEnv(const Root: Integer; const Sub: String);
var PathValue, NewPath, Name, CurValue, Rest: String;
begin
  PathValue := '';
  if RegQueryStringValue(Root, Sub, 'Path', PathValue) then
  begin
    NewPath := PathFilterOut(PathValue, True, False);
    if NewPath <> PathValue then WritePathValue(Root, Sub, NewPath);
  end;

  Rest := HomeVarNames;
  while Rest <> '' do
  begin
    Name := TakeEntry(Rest);
    CurValue := '';
    if RegQueryStringValue(Root, Sub, Name, CurValue) then
      if IsUnderApp(CurValue) then RegDeleteValue(Root, Sub, Name);
  end;
end;

procedure RemoveEnvironment();
begin
  RemoveHiveEnv(HKLM, SysEnvSubKey());
  RemoveHiveEnv(HKCU, UserEnvSubKey());
  BroadcastEnvironmentChange();
end;

// Python 用的是 embeddable 包，它有两个坑：
//   1) 不带 pip（连 ensurepip 都没有，所以只能用官方 get-pip.py）；
//   2) python3xx._pth 里 "import site" 是注释掉的，导致 Lib\site-packages
//      根本不在 sys.path 上。
// 这里把 site 打开、再跑一次 get-pip.py。任何一步失败都只是"没有 pip"，
// 不影响 Python 本体，全部记进日志。
procedure EnsurePip();
var
  I, J, Rc: Integer;
  PyDir, Pth, GetPip, Exe: String;
  PthLines: TArrayOfString;
  FindRec: TFindRec;
  Found, HasSite: Boolean;
begin
  I := ToolIndexOf('Python');
  if I < 0 then Exit;
  if InstallVer(I) = '' then Exit;     // 没装 Python 就什么都不做

  PyDir := ExpandConstant('{app}\' + ToolSub[I] + '\' + InstallVer(I));
  Exe := PyDir + '\python.exe';
  if not FileExists(Exe) then begin Log('pip：找不到 ' + Exe + '，跳过'); Exit; end;

  // --- 1) 打开 site：往 python3xx._pth 里补一行 import site ---
  Found := False;
  if FindFirst(PyDir + '\python*._pth', FindRec) then
  begin
    repeat
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
      begin
        Found := True;
        Pth := PyDir + '\' + FindRec.Name;
        // ⚠ 必须逐行比对"整行是否等于 import site"。
        //   模板里本来就有一行被注释掉的 "#import site"，如果用 Pos 找子串会命中它，
        //   于是误判成"已经打开"、直接跳过，pip 就永远装不上了。
        HasSite := False;
        if LoadStringsFromFile(Pth, PthLines) then
          for J := 0 to GetArrayLength(PthLines) - 1 do
            if Trim(PthLines[J]) = 'import site' then HasSite := True;

        if HasSite then
          Log('pip：' + FindRec.Name + ' 里 site 已经是打开的')
        else if SaveStringToFile(Pth, #13#10 + 'import site' + #13#10, True) then
          Log('pip：已在 ' + FindRec.Name + ' 里打开 site')
        else
          Log('pip：' + FindRec.Name + ' 写入失败');
      end;
    until not FindNext(FindRec);
    FindClose(FindRec);
  end;
  if not Found then Log('pip：没找到 python*._pth，site 打不开，pip 可能无法导入');

  // --- 2) 下 get-pip.py 并执行 ---
  GetPip := ExpandConstant('{tmp}\get-pip.py');
  try
    DownloadTemporaryFile(PipUrl, 'get-pip.py', '', nil);
  except
    Log('pip：get-pip.py 下载失败，跳过装 pip（' + GetExceptionMessage + '）');
    Exit;
  end;
  if not FileExists(GetPip) then begin Log('pip：get-pip.py 没拿到，跳过'); Exit; end;

  if Exec(Exe, '"' + GetPip + '" --no-warn-script-location', PyDir, SW_HIDE,
          ewWaitUntilTerminated, Rc) then
  begin
    if Rc = 0 then Log('pip：安装完成')
    else Log('pip：get-pip.py 返回码 ' + IntToStr(Rc) + '，pip 可能没装上');
  end
  else
    Log('pip：执行 python.exe 失败');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not ExtractSelected() then
      Log('警告：有包解压失败');
  end;

  if CurStep = ssPostInstall then
  begin
    PromoteStaged();
    EnsurePhpIni();
    // ⚠ 必须在 ApplyEnvironment 之前：转发脚本是按目录内容现场生成的，
    //   pip 装晚了 Scripts\pip.exe 就扫不到，{app}\bin 里不会出现 pip.cmd。
    EnsurePip();
    // 不再有全局开关：要不要写环境变量由每个工具的下拉框决定，
    // ApplyEnvironment 内部用 EnvEnabled(I) 逐个判断，选"不设置变量"的工具一点不碰。
    ApplyEnvironment();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveEnvironment();
end;
