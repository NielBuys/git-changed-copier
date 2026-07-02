unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  Grids, Process, FileUtil, IniFiles, StrUtils, fpjson, jsonparser, LConvEncoding;

type

  { TMainFrm }

  TMainFrm = class(TForm)
    AddDependentFilesBtn: TButton;
    BaseFolderLbl: TLabel;
    CopiedFilesStringGrid: TStringGrid;
    CopyChangedFilesBtn: TButton;
    CancelBtn: TButton;
    DependentSQLFoldersEdt: TEdit;
    DependentSQLFoldersLbl: TLabel;
    EnvFileEdt: TEdit;
    EnvFileLbl: TLabel;
    ExportChangedFilesBtn: TButton;
    ExportRunLogBtn: TButton;
    LoginTimeoutEdt: TEdit;
    LoginTimeoutLbl: TLabel;
    QueryTimeoutEdt: TEdit;
    QueryTimeoutLbl: TLabel;
    RetriesEdt: TEdit;
    RetriesLbl: TLabel;
    RetryWaitEdt: TEdit;
    RetryWaitLbl: TLabel;
    FiltersEdt: TEdit;
    FiltersLbl: TLabel;
    FromBaseFolderEdt: TEdit;
    FromBaseFolderLbl: TLabel;
    FromTagEdt: TEdit;
    FromTagLbl: TLabel;
    LoadFailedBtn: TButton;
    OpenDialog1: TOpenDialog;
    GenerateBtn: TButton;
    GenerateSingleFileTab: TTabSheet;
    GenFromTagEdt: TEdit;
    GenFromTagLbl: TLabel;
    GenInfoHdrLbl: TLabel;
    GenLogMemo: TMemo;
    GenOutFileEdt: TEdit;
    GenOutFileLbl: TLabel;
    GenProgressBar: TProgressBar;
    GenRepoEdt: TEdit;
    GenRepoLbl: TLabel;
    GenSqlFolderEdt: TEdit;
    GenSqlFolderLbl: TLabel;
    GenToTagEdt: TEdit;
    GenToTagLbl: TLabel;
    MainSQLFolderEdt: TEdit;
    MainSQLFolderLbl: TLabel;
    OnlyFailedChk: TCheckBox;
    PageControl1: TPageControl;
    CopyChangedGitFilesTab: TTabSheet;
    PasswordEdt: TEdit;
    PasswordLbl: TLabel;
    PassesEdt: TEdit;
    PassesLbl: TLabel;
    ProgressBar1: TProgressBar;
    RunBtn: TButton;
    RunDatabasesTab: TTabSheet;
    RunEnvFileEdt: TEdit;
    RunEnvFileLbl: TLabel;
    RunLogMemo: TMemo;
    RunProgressBar: TProgressBar;
    RunResultsGrid: TStringGrid;
    RunSqlFileEdt: TEdit;
    RunSqlFileLbl: TLabel;
    SaveDialog1: TSaveDialog;
    ServerEdt: TEdit;
    ServerLbl: TLabel;
    ToBaseFolderEdt: TEdit;
    ToGitTagEdt: TEdit;
    ToGitTagLbl: TLabel;
    UserEdt: TEdit;
    UserLbl: TLabel;
    WindowsAuthChk: TCheckBox;
    procedure AddDependentFilesBtnClick(Sender: TObject);
    procedure CopyChangedFilesBtnClick(Sender: TObject);
    procedure ExportChangedFilesBtnClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure GenerateBtnClick(Sender: TObject);
    procedure RunBtnClick(Sender: TObject);
    procedure WindowsAuthChkChange(Sender: TObject);
    procedure PageControl1Change(Sender: TObject);
    procedure EnvFileEdtChange(Sender: TObject);
    procedure ExportRunLogBtnClick(Sender: TObject);
    procedure LoadFailedBtnClick(Sender: TObject);
    procedure CancelBtnClick(Sender: TObject);
  private
    FLastFailedDbs: TStringList; // databases that failed on the previous run (this session)
    FRunning: Boolean;           // a run is in progress
    FCancelRequested: Boolean;   // user asked to stop the run
    function LooksLikeConnectivityFailure(const AOutput: string): Boolean;
    procedure InterruptibleSleep(ASeconds: Integer);
    function FolderHasAnyFiles(const Dir: string): Boolean;
    function SanitizeFileName(const AName: string): string;
    function ReleaseDestFolder: string;
    function SingleFileOutputPath: string;
    procedure RefreshGenerateTabInfo;
    procedure WriteLinesFile(const APath, AHeader: string; ALines: TStrings);
    function IndexedName(const APath: string; N: Integer): string;
    function ReadJSONStringField(const AFileName, AField: string): string;
    procedure StreamWriteText(AStream: TStream; const AText: string);
    procedure StreamAppendFile(AStream: TStream; const AFileName: string);
    procedure PopulateProcEnv(AEnv: TStrings; const AExtraName, AExtraValue: string);
    function RunSqlcmd(const AServer, ADatabase, AUser, APassword, ASqlFile: string;
      AWindowsAuth: Boolean; ALoginTimeout, AQueryTimeout: Integer;
      out AOutput: string): Integer;
    function CountSqlErrors(const AOutput: string): Integer;
    function GetChangedFilesList(
      const FromGitTag, FromBasePath, FileFilter: string): TStringList;
    function CopyFilesToDest(Files: TStringList;
      const FromBasePath, DestDir: string): TStringList;
    function FindDependentEquivalents(ChangedFiles: TStringList;
      const FromBasePath, MainSQLRel, DependentRels: string): TStringList;
    function NormalizedName(const AName: string): string;
    procedure ShowFilesInGrid(Files: TStringList);
  public

  end;

var
  MainFrm: TMainFrm;

implementation

{$R *.lfm}

{ TMainFrm }

procedure TMainFrm.CopyChangedFilesBtnClick(Sender: TObject);
var
  ChangedFiles, Copied: TStringList;
  DestDir: string;
begin
  DestDir := IncludeTrailingPathDelimiter(ToBaseFolderEdt.Text) + ToGitTagEdt.Text;

  // Check if destination folder exists and is not empty
  if DirectoryExists(DestDir) and FolderHasAnyFiles(DestDir) then
  begin
    ShowMessage('Destination folder "' + DestDir + '" already exists and is not empty.');
    Exit;
  end;

  ChangedFiles := GetChangedFilesList(
    FromTagEdt.Text,          // the tag to diff from
    FromBaseFolderEdt.Text,   // path to Git repo (repo root)
    FiltersEdt.Text);         // extension filter, e.g. *.sql (blank / *.* = all)
  try
    Copied := CopyFilesToDest(ChangedFiles, FromBaseFolderEdt.Text, DestDir);
    try
      ShowFilesInGrid(Copied);
      // Save the change-set list into the release folder for the audit trail.
      WriteLinesFile(IncludeTrailingPathDelimiter(DestDir) +
        SanitizeFileName(Trim(ToGitTagEdt.Text)) + '_ChangedFiles.csv',
        'Changed SQL Files', Copied);
    finally
      Copied.Free;
    end;
  finally
    ChangedFiles.Free;
  end;
end;

procedure TMainFrm.AddDependentFilesBtnClick(Sender: TObject);
var
  ChangedFiles, Deps, Copied: TStringList;
  DestDir: string;
begin
  if Trim(MainSQLFolderEdt.Text) = '' then
  begin
    ShowMessage('Please enter the Main SQL Folder (e.g. SQL\WineMS2).');
    Exit;
  end;
  if Trim(DependentSQLFoldersEdt.Text) = '' then
  begin
    ShowMessage('Please enter one or more Dependent SQL Folders ' +
      '(e.g. SQL\JuiceMS;SQL\OliveMS;SQL\FarmMS).');
    Exit;
  end;

  DestDir := IncludeTrailingPathDelimiter(ToBaseFolderEdt.Text) + ToGitTagEdt.Text;

  // Re-run the same diff used by "Copy Changed Files" to know which main files changed.
  ChangedFiles := GetChangedFilesList(
    FromTagEdt.Text, FromBaseFolderEdt.Text, FiltersEdt.Text);
  try
    // For each changed file under the main SQL folder, find files with the same
    // name in the dependent folders (the module-specific version of that object).
    Deps := FindDependentEquivalents(ChangedFiles, FromBaseFolderEdt.Text,
      MainSQLFolderEdt.Text, DependentSQLFoldersEdt.Text);
    try
      Copied := CopyFilesToDest(Deps, FromBaseFolderEdt.Text, DestDir);
      try
        ShowFilesInGrid(Copied);
        // Save the dependent-file list into the release folder for the audit trail.
        WriteLinesFile(IncludeTrailingPathDelimiter(DestDir) +
          SanitizeFileName(Trim(ToGitTagEdt.Text)) + '_DependentFiles.csv',
          'Dependent SQL Files', Copied);
        ShowMessage(Format(
          'Added %d dependent file(s) matching %d changed main file(s).',
          [Copied.Count, ChangedFiles.Count]));
      finally
        Copied.Free;
      end;
    finally
      Deps.Free;
    end;
  finally
    ChangedFiles.Free;
  end;
end;

procedure TMainFrm.ExportChangedFilesBtnClick(Sender: TObject);
var
  SL: TStringList;
  Row: Integer;
  FileName: string;
begin
  if CopiedFilesStringGrid.RowCount <= 1 then
  begin
    ShowMessage('There are no copied files to export.');
    Exit;
  end;

  // Setup SaveDialog1
  SaveDialog1.Title := 'Save CSV File';
  SaveDialog1.DefaultExt := 'csv';
  SaveDialog1.Filter := 'CSV Files (*.csv)|*.csv';
  SaveDialog1.FileName := 'CopiedFiles' + ToGitTagEdt.Text + '.csv';

  if SaveDialog1.Execute then
  begin
    FileName := SaveDialog1.FileName;
    SL := TStringList.Create;
    try
      // Add header
      SL.Add('Copied SQL Files');

      // Add each row
      for Row := 1 to CopiedFilesStringGrid.RowCount - 1 do
        SL.Add(CopiedFilesStringGrid.Cells[0, Row]);

      // Save to file
      SL.SaveToFile(FileName);
      ShowMessage('CSV file saved to:' + sLineBreak + FileName);
    finally
      SL.Free;
    end;
  end;
end;

procedure TMainFrm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := ChangeFileExt(Application.ExeName, '.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('Settings', 'ToBaseFolder', ToBaseFolderEdt.Text);
    Ini.WriteString('Settings', 'FromBaseFolder', FromBaseFolderEdt.Text);
    Ini.WriteString('Settings', 'ToGitTag', ToGitTagEdt.Text);
    Ini.WriteString('Settings', 'FromTag', FromTagEdt.Text);
    Ini.WriteString('Settings', 'Filters', FiltersEdt.Text);
    Ini.WriteString('Settings', 'MainSQLFolder', MainSQLFolderEdt.Text);
    Ini.WriteString('Settings', 'DependentSQLFolders', DependentSQLFoldersEdt.Text);
    Ini.WriteString('Settings', 'EnvFile', EnvFileEdt.Text);
    Ini.WriteString('Settings', 'Passes', PassesEdt.Text);
    Ini.WriteString('Settings', 'Server', ServerEdt.Text);
    Ini.WriteString('Settings', 'User', UserEdt.Text);
    Ini.WriteString('Settings', 'Password', PasswordEdt.Text);
    Ini.WriteBool('Settings', 'WindowsAuth', WindowsAuthChk.Checked);
    Ini.WriteString('Settings', 'RunEnvFile', RunEnvFileEdt.Text);
    Ini.WriteString('Settings', 'RunSqlFile', RunSqlFileEdt.Text);
    Ini.WriteString('Settings', 'LoginTimeout', LoginTimeoutEdt.Text);
    Ini.WriteString('Settings', 'QueryTimeout', QueryTimeoutEdt.Text);
    Ini.WriteString('Settings', 'Retries', RetriesEdt.Text);
    Ini.WriteString('Settings', 'RetryWait', RetryWaitEdt.Text);
  finally
    Ini.Free;
  end;
  FLastFailedDbs.Free; // TObject.Free is safe when nil
end;

procedure TMainFrm.FormShow(Sender: TObject);
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := ChangeFileExt(Application.ExeName, '.ini');
  if FileExists(IniPath) then
  begin
    Ini := TIniFile.Create(IniPath);
    try
      ToBaseFolderEdt.Text := Ini.ReadString('Settings', 'ToBaseFolder', '');
      FromBaseFolderEdt.Text := Ini.ReadString('Settings', 'FromBaseFolder', '');
      ToGitTagEdt.Text := Ini.ReadString('Settings', 'ToGitTag', '');
      FromTagEdt.Text := Ini.ReadString('Settings', 'FromTag', '');
      FiltersEdt.Text := Ini.ReadString('Settings', 'Filters', '');
      MainSQLFolderEdt.Text := Ini.ReadString('Settings', 'MainSQLFolder', '');
      DependentSQLFoldersEdt.Text := Ini.ReadString('Settings', 'DependentSQLFolders', '');
      EnvFileEdt.Text := Ini.ReadString('Settings', 'EnvFile', '');
      PassesEdt.Text := Ini.ReadString('Settings', 'Passes', '1');
      ServerEdt.Text := Ini.ReadString('Settings', 'Server', '');
      UserEdt.Text := Ini.ReadString('Settings', 'User', '');
      PasswordEdt.Text := Ini.ReadString('Settings', 'Password', '');
      WindowsAuthChk.Checked := Ini.ReadBool('Settings', 'WindowsAuth', False);
      RunEnvFileEdt.Text := Ini.ReadString('Settings', 'RunEnvFile', '');
      RunSqlFileEdt.Text := Ini.ReadString('Settings', 'RunSqlFile', '');
      LoginTimeoutEdt.Text := Ini.ReadString('Settings', 'LoginTimeout', '15');
      QueryTimeoutEdt.Text := Ini.ReadString('Settings', 'QueryTimeout', '300');
      RetriesEdt.Text := Ini.ReadString('Settings', 'Retries', '1');
      RetryWaitEdt.Text := Ini.ReadString('Settings', 'RetryWait', '15');
    finally
      Ini.Free;
    end;
  end;
  WindowsAuthChkChange(nil); // sync User/Password enabled state
  RefreshGenerateTabInfo;    // show Tab 1 details on the generate tab
end;

{ Runs `git diff --name-only <FromGitTag> HEAD` in FromBasePath and returns the
  changed file paths (relative to the repo root) that match the extension filter.
  Paths are normalized to the Windows path delimiter. }
function TMainFrm.GetChangedFilesList(
  const FromGitTag, FromBasePath, FileFilter: string): TStringList;
var
  GitProcess: TProcess;
  OutputLines: TStringList;
  OutputStream: TMemoryStream;
  Buffer: array[0..2047] of byte;
  BytesRead: LongInt;
  i: Integer;
  FileName, FilterExt: string;
begin
  Result := TStringList.Create;
  OutputLines := TStringList.Create;
  OutputStream := TMemoryStream.Create;
  GitProcess := TProcess.Create(nil);
  try
    GitProcess.Executable := 'git';
    GitProcess.Options := [poUsePipes, poNoConsole];
    GitProcess.CurrentDirectory := FromBasePath;
    GitProcess.Parameters.Add('diff');
    GitProcess.Parameters.Add('--name-only');
    GitProcess.Parameters.Add(FromGitTag);
    GitProcess.Parameters.Add('HEAD');
    GitProcess.Execute;

    // Read the full output from Git to avoid truncation
    while GitProcess.Running do
    begin
      if GitProcess.Output.NumBytesAvailable > 0 then
      begin
        BytesRead := GitProcess.Output.Read(Buffer, SizeOf(Buffer));
        OutputStream.Write(Buffer, BytesRead);
      end
      else
        Sleep(10);
    end;

    // Final read after process ends
    while GitProcess.Output.NumBytesAvailable > 0 do
    begin
      BytesRead := GitProcess.Output.Read(Buffer, SizeOf(Buffer));
      OutputStream.Write(Buffer, BytesRead);
    end;

    OutputStream.Position := 0;
    OutputLines.LoadFromStream(OutputStream);

    // Normalize extension filter (e.g., '*.sql' -> '.sql'). Blank, '*' or '*.*' = all.
    FilterExt := LowerCase(ExtractFileExt(FileFilter));

    for i := 0 to OutputLines.Count - 1 do
    begin
      FileName := Trim(OutputLines[i]);
      if FileName = '' then
        Continue;

      // Git reports forward slashes; convert so nested folders are created correctly.
      FileName := StringReplace(FileName, '/', PathDelim, [rfReplaceAll]);

      if (FilterExt = '') or (FilterExt = '.*') or
         (LowerCase(ExtractFileExt(FileName)) = FilterExt) then
        Result.Add(FileName);
    end;
  finally
    GitProcess.Free;
    OutputLines.Free;
    OutputStream.Free;
  end;
end;

{ Copies each relative file from FromBasePath into DestDir, preserving the folder
  structure. Drives the progress bar. Returns the list of files actually copied. }
function TMainFrm.CopyFilesToDest(Files: TStringList;
  const FromBasePath, DestDir: string): TStringList;
var
  i: Integer;
  FileName, SrcFilePath, DestFilePath: string;
begin
  Result := TStringList.Create;

  ForceDirectories(DestDir);

  ProgressBar1.Min := 0;
  ProgressBar1.Max := Files.Count;
  ProgressBar1.Position := 0;

  for i := 0 to Files.Count - 1 do
  begin
    FileName := Files[i];
    SrcFilePath := IncludeTrailingPathDelimiter(FromBasePath) + FileName;
    DestFilePath := IncludeTrailingPathDelimiter(DestDir) + FileName;

    ForceDirectories(ExtractFilePath(DestFilePath));

    if FileExists(SrcFilePath) then
    begin
      if CopyFile(SrcFilePath, DestFilePath) then
        Result.Add(FileName);
    end;

    ProgressBar1.Position := i + 1;
    Application.ProcessMessages;
  end;
end;

{ For every changed file located under MainSQLRel, look up files with a matching
  name inside each of the DependentRels folders (';'-separated, relative to the
  repo root) and return their repo-relative paths. These are the module-specific
  versions (e.g. JuiceMS) of an object whose main (WineMS2) version changed but
  whose own copy was not touched in git.

  Matching ignores a leading run-order prefix (1-2 digits + '_', e.g. '1_' in
  '1_vwDispatches.sql') on either side, so '0_vwProduct.sql' matches 'vwProduct.sql'.
  See NormalizedName for the details. }
function TMainFrm.FindDependentEquivalents(ChangedFiles: TStringList;
  const FromBasePath, MainSQLRel, DependentRels: string): TStringList;
var
  DepList, DepFiles, DepRel_paths, DepNorms: TStringList;
  FromDelim, MainPrefix, ChangedRel, ChangedNorm, DepRel, DepAbs, MatchRel: string;
  i, d, k: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;              // de-duplicate: the same dependent file
  Result.Duplicates := dupIgnore;     // is only added once.

  FromDelim := IncludeTrailingPathDelimiter(FromBasePath);

  if Trim(MainSQLRel) = '' then
    MainPrefix := ''  // empty = consider every changed file
  else
    MainPrefix := IncludeTrailingPathDelimiter(
      StringReplace(Trim(MainSQLRel), '/', PathDelim, [rfReplaceAll]));

  DepList := TStringList.Create;
  DepRel_paths := TStringList.Create;  // every dependent file, repo-relative
  DepNorms := TStringList.Create;      // parallel list of normalized names
  try
    // 1. Enumerate every file in the dependent folders once, up front.
    DepList.Delimiter := ';';
    DepList.StrictDelimiter := True;
    DepList.DelimitedText := DependentRels;

    for d := 0 to DepList.Count - 1 do
    begin
      DepRel := Trim(DepList[d]);
      if DepRel = '' then
        Continue;
      DepRel := StringReplace(DepRel, '/', PathDelim, [rfReplaceAll]);
      DepAbs := FromDelim + IncludeTrailingPathDelimiter(DepRel);
      if not DirectoryExists(DepAbs) then
        Continue;

      DepFiles := FindAllFiles(DepAbs, '', True); // all files, recursively
      try
        for k := 0 to DepFiles.Count - 1 do
        begin
          MatchRel := DepFiles[k];
          // Convert the absolute path back to a repo-relative path.
          if SameText(Copy(MatchRel, 1, Length(FromDelim)), FromDelim) then
            MatchRel := Copy(MatchRel, Length(FromDelim) + 1, MaxInt);
          DepRel_paths.Add(MatchRel);
          DepNorms.Add(NormalizedName(MatchRel));
        end;
      finally
        DepFiles.Free;
      end;
    end;

    // 2. For each changed main file, add every dependent file with a matching name.
    for i := 0 to ChangedFiles.Count - 1 do
    begin
      ChangedRel := ChangedFiles[i]; // already normalized to PathDelim

      // Only consider files that live under the main SQL folder.
      if (MainPrefix <> '') and
         (not SameText(Copy(ChangedRel, 1, Length(MainPrefix)), MainPrefix)) then
        Continue;

      ChangedNorm := NormalizedName(ChangedRel);
      if ChangedNorm = '' then
        Continue;

      for k := 0 to DepRel_paths.Count - 1 do
        if DepNorms[k] = ChangedNorm then
          Result.Add(DepRel_paths[k]);
    end;
  finally
    DepList.Free;
    DepRel_paths.Free;
    DepNorms.Free;
  end;
end;

{ Returns a file's base name, lower-cased, with a leading run-order prefix removed.
  A run-order prefix is 1 or 2 digits followed by '_' (e.g. '1_', '06_'). Longer
  numeric prefixes are left intact so date-stamped migration scripts
  (e.g. '20200522_...') and migration numbers (e.g. '1464_...') are NOT stripped
  and therefore only match files with the identical stamp. }
function TMainFrm.NormalizedName(const AName: string): string;
var
  S: string;
  Digits: Integer;
begin
  S := ExtractFileName(AName);

  Digits := 0;
  while (Digits < Length(S)) and (Digits < 2) and (S[Digits + 1] in ['0'..'9']) do
    Inc(Digits);

  // Strip only when the digit run is 1-2 long AND immediately followed by '_'.
  if (Digits > 0) and (Digits < Length(S)) and (S[Digits + 1] = '_') then
    Delete(S, 1, Digits + 1);

  Result := LowerCase(S);
end;

{ Replaces the result grid with the given list of files. Both the changed files
  (Copy Changed Files) and the dependent files (Add Dependent Files) are shown
  here, one set at a time, so either can be exported. }
procedure TMainFrm.ShowFilesInGrid(Files: TStringList);
var
  i: Integer;
begin
  CopiedFilesStringGrid.ColCount := 1;
  CopiedFilesStringGrid.ColWidths[0] := 300;

  CopiedFilesStringGrid.RowCount := Files.Count + 1; // row 0 is the header
  CopiedFilesStringGrid.Cells[0, 0] := 'Copied SQL Files';
  if CopiedFilesStringGrid.RowCount > 1 then
    CopiedFilesStringGrid.FixedRows := 1;

  for i := 0 to Files.Count - 1 do
    CopiedFilesStringGrid.Cells[0, i + 1] := Files[i];
end;

function TMainFrm.FolderHasAnyFiles(const Dir: string): Boolean;
var
  SR: TSearchRec;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) = faDirectory then
        begin
          // Recursively check subfolders
          if FolderHasAnyFiles(IncludeTrailingPathDelimiter(Dir) + SR.Name) then
          begin
            Result := True;
            Break;
          end;
        end
        else
        begin
          Result := True;
          Break;
        end;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

{ Reads a single top-level string field from a JSON file. Returns '' if the file
  is missing/invalid or the field is absent. }
function TMainFrm.ReadJSONStringField(const AFileName, AField: string): string;
var
  SL: TStringList;
  Data: TJSONData;
begin
  Result := '';
  if not FileExists(AFileName) then
    Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(AFileName);
    try
      Data := GetJSON(SL.Text);
      try
        if Data is TJSONObject then
          Result := TJSONObject(Data).Get(AField, '');
      finally
        Data.Free;
      end;
    except
      Result := ''; // malformed JSON
    end;
  finally
    SL.Free;
  end;
end;

{ Writes raw text (ASCII/UTF-8 bytes) to a stream. }
procedure TMainFrm.StreamWriteText(AStream: TStream; const AText: string);
begin
  if AText <> '' then
    AStream.WriteBuffer(AText[1], Length(AText));
end;

{ Appends a source file to the stream, converting it to UTF-8 first. Source files
  are a mix of ASCII, UTF-8 and UTF-16 LE (some views carry a UTF-16 BOM). Left as
  raw bytes the combined file would mix encodings and sqlcmd (-f 65001) would fail
  with "Incorrect syntax near '?'". Normalising every file to UTF-8 gives the output
  one consistent encoding. }
procedure TMainFrm.StreamAppendFile(AStream: TStream; const AFileName: string);
var
  FS: TFileStream;
  Raw, Utf8, Enc: string;
  Encoded: Boolean;
begin
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Raw, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Raw[1], FS.Size);
  finally
    FS.Free;
  end;
  if Raw = '' then
    Exit;

  Enc := GuessEncoding(Raw);                       // detects UTF-16/UTF-8 BOMs, ANSI
  Utf8 := ConvertEncodingToUTF8(Raw, Enc, Encoded);
  // Strip a leading UTF-8 BOM so it does not land mid-file.
  if (Length(Utf8) >= 3) and (Utf8[1] = #$EF) and (Utf8[2] = #$BB) and (Utf8[3] = #$BF) then
    Delete(Utf8, 1, 3);

  StreamWriteText(AStream, Utf8);
end;

{ Replaces characters that are invalid in a Windows file name with '_'. }
function TMainFrm.SanitizeFileName(const AName: string): string;
const
  Invalid = '\/:*?"<>|';
var
  i: Integer;
begin
  Result := AName;
  for i := 1 to Length(Result) do
    if Pos(Result[i], Invalid) > 0 then
      Result[i] := '_';
end;

{ Writes an optional header line followed by the given lines to APath. }
procedure TMainFrm.WriteLinesFile(const APath, AHeader: string; ALines: TStrings);
var
  SL: TStringList;
  i: Integer;
begin
  SL := TStringList.Create;
  try
    if AHeader <> '' then
      SL.Add(AHeader);
    for i := 0 to ALines.Count - 1 do
      SL.Add(ALines[i]);
    ForceDirectories(ExtractFilePath(APath));
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

{ Builds a path with "_N" inserted before the extension, e.g.
  ...\foo_RunResults.csv + 2 -> ...\foo_RunResults_2.csv }
function TMainFrm.IndexedName(const APath: string; N: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(APath)) +
    ChangeFileExt(ExtractFileName(APath), '') + '_' + IntToStr(N) + ExtractFileExt(APath);
end;

{ Exports the current run log to a file chosen by the user (defaults to the release
  folder next to the SQL file). }
procedure TMainFrm.ExportRunLogBtnClick(Sender: TObject);
begin
  if RunLogMemo.Lines.Count = 0 then
  begin
    ShowMessage('There is no run output to export yet.');
    Exit;
  end;
  SaveDialog1.Title := 'Export Run Log';
  SaveDialog1.DefaultExt := 'txt';
  SaveDialog1.Filter := 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*';
  if Trim(RunSqlFileEdt.Text) <> '' then
  begin
    SaveDialog1.InitialDir := ExtractFilePath(RunSqlFileEdt.Text);
    SaveDialog1.FileName :=
      ChangeFileExt(ExtractFileName(RunSqlFileEdt.Text), '') + '_RunLog.txt';
  end
  else
    SaveDialog1.FileName := 'RunLog.txt';

  if SaveDialog1.Execute then
  begin
    RunLogMemo.Lines.SaveToFile(SaveDialog1.FileName);
    ShowMessage('Run log saved to:' + sLineBreak + SaveDialog1.FileName);
  end;
end;

{ Loads the failed (ERROR) databases from a run's _RunResults.csv into the failed list
  and ticks "Re-run failed only", so a failed set can be re-run in a new session (the
  in-memory list does not survive an app restart). The results file is detected
  automatically next to the SQL File; a file dialog is only shown as a fallback. }
procedure TMainFrm.LoadFailedBtnClick(Sender: TObject);
var
  CsvLines: TStringList;
  i, p1, p2: Integer;
  L, Rest, Db, Src: string;
begin
  Src := '';
  // Detect the results file next to the SQL File: <sqlfile-name>_RunResults.csv
  if Trim(RunSqlFileEdt.Text) <> '' then
  begin
    Src := IncludeTrailingPathDelimiter(ExtractFilePath(RunSqlFileEdt.Text)) +
      ChangeFileExt(ExtractFileName(RunSqlFileEdt.Text), '') + '_RunResults.csv';
    if not FileExists(Src) then
      Src := '';
  end;

  // Fall back to asking only if it could not be detected.
  if Src = '' then
  begin
    OpenDialog1.Title := 'Load Failed Databases From Run Results CSV';
    OpenDialog1.Filter :=
      'Run Results (*_RunResults.csv)|*_RunResults.csv|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    if Trim(RunSqlFileEdt.Text) <> '' then
      OpenDialog1.InitialDir := ExtractFilePath(RunSqlFileEdt.Text);
    if not OpenDialog1.Execute then
      Exit;
    Src := OpenDialog1.FileName;
  end;

  if FLastFailedDbs = nil then
    FLastFailedDbs := TStringList.Create;
  FLastFailedDbs.Clear;

  CsvLines := TStringList.Create;
  try
    CsvLines.LoadFromFile(Src);
    // Rows look like:  "DbName","ERROR","6"   (header on the first line is skipped)
    for i := 1 to CsvLines.Count - 1 do
    begin
      L := Trim(CsvLines[i]);
      if L = '' then
        Continue;
      if Pos('"ERROR"', L) = 0 then
        Continue; // only failed rows
      // database name is the first quoted field
      p1 := Pos('"', L);
      if p1 = 0 then
        Continue;
      Rest := Copy(L, p1 + 1, MaxInt);
      p2 := Pos('"', Rest);
      if p2 <= 1 then
        Continue;
      Db := Trim(Copy(Rest, 1, p2 - 1));
      if Db <> '' then
        FLastFailedDbs.Add(Db);
    end;
  finally
    CsvLines.Free;
  end;

  if FLastFailedDbs.Count = 0 then
  begin
    ShowMessage('No failed (ERROR) rows found in:' + sLineBreak + Src);
    Exit;
  end;

  // Show the loaded set and arm the re-run tick.
  RunResultsGrid.ColCount := 3;
  RunResultsGrid.RowCount := FLastFailedDbs.Count + 1;
  RunResultsGrid.Cells[0, 0] := 'Database';
  RunResultsGrid.Cells[1, 0] := 'Result';
  RunResultsGrid.Cells[2, 0] := 'Errors';
  RunResultsGrid.FixedRows := 1;
  for i := 0 to FLastFailedDbs.Count - 1 do
  begin
    RunResultsGrid.Cells[0, i + 1] := FLastFailedDbs[i];
    RunResultsGrid.Cells[1, i + 1] := 'loaded';
    RunResultsGrid.Cells[2, i + 1] := '';
  end;
  OnlyFailedChk.Checked := True;

  RunLogMemo.Lines.Add('Loaded ' + IntToStr(FLastFailedDbs.Count) +
    ' failed database(s) from ' + ExtractFileName(Src) +
    '. "Re-run failed only" is ticked - click "Run on All Databases".');
  ShowMessage(Format('Loaded %d failed database(s).' + sLineBreak +
    '"Re-run failed only" is now ticked - click "Run on All Databases" to run just those.',
    [FLastFailedDbs.Count]));
end;

{ The folder that "Copy Changed Files" wrote the change set into:
  <To Base Folder Path>\<To Git Tag>. Empty if either field is blank. }
function TMainFrm.ReleaseDestFolder: string;
begin
  Result := '';
  if (Trim(ToBaseFolderEdt.Text) = '') or (Trim(ToGitTagEdt.Text) = '') then
    Exit;
  Result := IncludeTrailingPathDelimiter(Trim(ToBaseFolderEdt.Text)) + Trim(ToGitTagEdt.Text);
end;

{ Full path of the single file to generate: saved into the release folder with an
  audit-friendly name embedding the release tag, environment and start tag, e.g.
  <ToTag>_<Env>_from_<FromTag>.sql }
function TMainFrm.SingleFileOutputPath: string;
var
  Dest, EnvName, FromTag, ToTag, FName: string;
begin
  Result := '';
  Dest := ReleaseDestFolder;
  if Dest = '' then
    Exit;
  EnvName := '';
  if Trim(EnvFileEdt.Text) <> '' then
    EnvName := ChangeFileExt(ExtractFileName(Trim(EnvFileEdt.Text)), '');
  FromTag := Trim(FromTagEdt.Text);
  ToTag := Trim(ToGitTagEdt.Text);

  FName := ToTag;
  if EnvName <> '' then
    FName := FName + '_' + EnvName;
  if FromTag <> '' then
    FName := FName + '_from_' + FromTag;
  if FName = '' then
    FName := 'SingleFile';
  Result := IncludeTrailingPathDelimiter(Dest) + SanitizeFileName(FName) + '.sql';
end;

{ Mirrors the Copy Changed Files tab's details onto the Generate tab (read-only) and
  computes the derived SQL source folder and output file path for review. }
procedure TMainFrm.RefreshGenerateTabInfo;
var
  Dest: string;
begin
  // Guard against OnChange firing while the form is still streaming from the .lfm,
  // when not all controls exist yet.
  if csLoading in ComponentState then
    Exit;
  GenRepoEdt.Text := Trim(FromBaseFolderEdt.Text);
  GenFromTagEdt.Text := Trim(FromTagEdt.Text);
  GenToTagEdt.Text := Trim(ToGitTagEdt.Text);
  Dest := ReleaseDestFolder;
  if Dest <> '' then
    GenSqlFolderEdt.Text := IncludeTrailingPathDelimiter(Dest) + 'SQL'
  else
    GenSqlFolderEdt.Text := '';
  GenOutFileEdt.Text := SingleFileOutputPath;
end;

{ Refresh the Generate tab's read-only details whenever it becomes visible. }
procedure TMainFrm.PageControl1Change(Sender: TObject);
begin
  if PageControl1.ActivePage = GenerateSingleFileTab then
    RefreshGenerateTabInfo;
end;

{ The environment (and passes) affect the derived output file name shown for review. }
procedure TMainFrm.EnvFileEdtChange(Sender: TObject);
begin
  RefreshGenerateTabInfo;
end;

{ Builds a single consolidated .sql file for an environment, in the same order the
  SQLUpdate runner uses: the environment's "Scripts" list (module order) -> each
  module's Config/Scripts/<module>.json "Folders" list (folder order) -> the *.sql
  files in each folder sorted by name (non-recursive). Files are separated by GO so
  each object is its own batch and a failure in one does not stop the rest. The
  whole ordered set is emitted "Passes" times so forward dependencies can resolve
  in a single execution. }
procedure TMainFrm.GenerateBtnClick(Sender: TObject);
var
  SqlRoot, EnvFile, ScriptsDir, EnvName, Databases, ScriptsCsv: string;
  DefFile, ModuleFolderName, FoldersCsv, FolderDir, RelLabel: string;
  DestFolder, OutFile: string;
  ScriptNames, Folders, SqlFiles: TStringList;
  OutStream: TFileStream;
  Passes, p, si, fi, gi, IncludedPerPass: Integer;

  procedure SplitCsv(const S: string; List: TStringList);
  begin
    List.Clear;
    List.Delimiter := ',';
    List.StrictDelimiter := True; // keep spaces inside names (e.g. "Stored Procedures")
    List.DelimitedText := S;
  end;

begin
  RefreshGenerateTabInfo; // make the review fields reflect the current Tab 1 values

  // Source folder and output location are derived from the Copy Changed Files tab.
  DestFolder := ReleaseDestFolder;
  if DestFolder = '' then
  begin
    ShowMessage('Please fill in "To Base Folder Path" and "To Git Tag" on the ' +
      'Copy Changed Files tab first.');
    Exit;
  end;

  SqlRoot := IncludeTrailingPathDelimiter(DestFolder) + 'SQL';
  if not DirectoryExists(SqlRoot) then
  begin
    ShowMessage('SQL source folder not found:' + sLineBreak + SqlRoot + sLineBreak +
      sLineBreak + 'Run "Copy Changed Files" first so the changed scripts exist there.');
    Exit;
  end;

  EnvFile := Trim(EnvFileEdt.Text);
  if (EnvFile = '') or not FileExists(EnvFile) then
  begin
    ShowMessage('Please enter a valid Environment File.');
    Exit;
  end;

  Passes := StrToIntDef(Trim(PassesEdt.Text), 1);
  if Passes < 1 then
    Passes := 1;

  // Script definitions live in the "Scripts" folder next to the environment file.
  ScriptsDir := IncludeTrailingPathDelimiter(ExtractFilePath(EnvFile)) + 'Scripts';
  EnvName := ChangeFileExt(ExtractFileName(EnvFile), '');
  Databases := ReadJSONStringField(EnvFile, 'Databases');
  ScriptsCsv := ReadJSONStringField(EnvFile, 'Scripts'); // matches runner: "Scripts" only

  if Trim(ScriptsCsv) = '' then
  begin
    ShowMessage('The environment file has no "Scripts" list: ' + EnvFile);
    Exit;
  end;

  OutFile := SingleFileOutputPath;
  if FileExists(OutFile) then
    if MessageDlg('Overwrite existing file?', OutFile,
         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  ForceDirectories(DestFolder);

  GenLogMemo.Clear;
  ScriptNames := TStringList.Create;
  Folders := TStringList.Create;
  OutStream := TFileStream.Create(OutFile, fmCreate);
  try
    // File header - audit provenance for the release
    StreamWriteText(OutStream,
      '-- Single SQL file  (environment: ' + EnvName + ')' + sLineBreak +
      '-- Repository      : ' + Trim(FromBaseFolderEdt.Text) + sLineBreak +
      '-- From tag (start): ' + Trim(FromTagEdt.Text) + sLineBreak +
      '-- To tag (release): ' + Trim(ToGitTagEdt.Text) + sLineBreak +
      '-- SQL source      : ' + SqlRoot + sLineBreak +
      '-- Target databases: ' + Databases + sLineBreak +
      '-- Scripts (order) : ' + ScriptsCsv + sLineBreak +
      '-- Generated       : ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + sLineBreak +
      '-- Passes          : ' + IntToStr(Passes) + sLineBreak +
      'GO' + sLineBreak);

    GenLogMemo.Lines.Add('Environment : ' + EnvName);
    GenLogMemo.Lines.Add('From tag    : ' + Trim(FromTagEdt.Text));
    GenLogMemo.Lines.Add('To tag      : ' + Trim(ToGitTagEdt.Text));
    GenLogMemo.Lines.Add('Databases   : ' + Databases);
    GenLogMemo.Lines.Add('Scripts     : ' + ScriptsCsv);
    GenLogMemo.Lines.Add('Passes      : ' + IntToStr(Passes));
    GenLogMemo.Lines.Add('Output      : ' + OutFile);
    GenLogMemo.Lines.Add('');

    SplitCsv(ScriptsCsv, ScriptNames);
    ProgressBar1.Position := 0;
    GenProgressBar.Min := 0;
    GenProgressBar.Max := Passes;
    GenProgressBar.Position := 0;

    for p := 1 to Passes do
    begin
      StreamWriteText(OutStream, sLineBreak +
        '-- ===================== PASS ' + IntToStr(p) + ' =====================' +
        sLineBreak + 'GO' + sLineBreak);
      if Passes > 1 then
        GenLogMemo.Lines.Add('===== PASS ' + IntToStr(p) + ' =====');

      IncludedPerPass := 0;

      for si := 0 to ScriptNames.Count - 1 do
      begin
        if Trim(ScriptNames[si]) = '' then
          Continue;

        DefFile := IncludeTrailingPathDelimiter(ScriptsDir) + Trim(ScriptNames[si]) + '.json';
        if not FileExists(DefFile) then
        begin
          if p = 1 then
            GenLogMemo.Lines.Add('  [skip] missing script definition: ' + DefFile);
          Continue;
        end;

        ModuleFolderName := ReadJSONStringField(DefFile, 'Name');
        if ModuleFolderName = '' then
          ModuleFolderName := Trim(ScriptNames[si]);
        FoldersCsv := ReadJSONStringField(DefFile, 'Folders');

        SplitCsv(FoldersCsv, Folders);
        for fi := 0 to Folders.Count - 1 do
        begin
          if Trim(Folders[fi]) = '' then
            Continue;

          FolderDir := IncludeTrailingPathDelimiter(SqlRoot) +
            ModuleFolderName + PathDelim + Trim(Folders[fi]);
          if not DirectoryExists(FolderDir) then
            Continue;

          // Non-recursive, *.sql only, sorted by file name (matches the runner).
          SqlFiles := FindAllFiles(FolderDir, '*.sql', False);
          try
            SqlFiles.Sort;
            for gi := 0 to SqlFiles.Count - 1 do
            begin
              RelLabel := ModuleFolderName + PathDelim + Trim(Folders[fi]) +
                PathDelim + ExtractFileName(SqlFiles[gi]);
              StreamWriteText(OutStream, sLineBreak +
                '-- ===== ' + RelLabel + ' =====' + sLineBreak);
              StreamAppendFile(OutStream, SqlFiles[gi]);
              StreamWriteText(OutStream, sLineBreak + 'GO' + sLineBreak);
              Inc(IncludedPerPass);
              if p = 1 then
                GenLogMemo.Lines.Add('  ' + RelLabel);
            end;
          finally
            SqlFiles.Free;
          end;
        end;
      end;

      GenProgressBar.Position := p;
      Application.ProcessMessages;
    end;

    GenLogMemo.Lines.Add('');
    GenLogMemo.Lines.Add(Format('Done: %d file(s) per pass x %d pass(es) -> %s',
      [IncludedPerPass, Passes, OutFile]));
  finally
    OutStream.Free;
    ScriptNames.Free;
    Folders.Free;
  end;

  // Pre-fill the "Run On Databases" tab with what we just built.
  RunSqlFileEdt.Text := OutFile;
  if Trim(RunEnvFileEdt.Text) = '' then
    RunEnvFileEdt.Text := EnvFile;

  ShowMessage(Format('Generated single SQL file:' + sLineBreak + '%s' + sLineBreak +
    sLineBreak + '%d file(s) per pass, %d pass(es).',
    [OutFile, IncludedPerPass, Passes]));
end;

{ Enables/disables the User and Password fields based on the auth mode. }
procedure TMainFrm.WindowsAuthChkChange(Sender: TObject);
begin
  UserEdt.Enabled := not WindowsAuthChk.Checked;
  PasswordEdt.Enabled := not WindowsAuthChk.Checked;
end;

{ Fills AEnv with the current process environment plus an optional extra variable.
  Copying the full environment keeps PATH etc. so sqlcmd is still found. }
procedure TMainFrm.PopulateProcEnv(AEnv: TStrings; const AExtraName, AExtraValue: string);
var
  i: Integer;
begin
  AEnv.Clear;
  for i := 1 to GetEnvironmentVariableCount do
    AEnv.Add(GetEnvironmentString(i));
  if AExtraName <> '' then
    AEnv.Add(AExtraName + '=' + AExtraValue);
end;

{ Runs sqlcmd against a single database, executing ASqlFile. The whole output
  (stdout + stderr) is captured into AOutput. The password is passed via the
  SQLCMDPASSWORD environment variable so it never appears on the command line.
  Returns the process exit code, or -2 if sqlcmd could not be launched. }
function TMainFrm.RunSqlcmd(const AServer, ADatabase, AUser, APassword, ASqlFile: string;
  AWindowsAuth: Boolean; ALoginTimeout, AQueryTimeout: Integer;
  out AOutput: string): Integer;
var
  Proc: TProcess;
  OutStream: TMemoryStream;
  Buffer: array[0..4095] of byte;
  BytesRead: LongInt;
begin
  Result := -2;
  AOutput := '';
  Proc := TProcess.Create(nil);
  OutStream := TMemoryStream.Create;
  try
    Proc.Executable := 'sqlcmd';
    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    Proc.Parameters.Add('-S'); Proc.Parameters.Add(AServer);
    Proc.Parameters.Add('-d'); Proc.Parameters.Add(ADatabase);
    if AWindowsAuth then
      Proc.Parameters.Add('-E')
    else
    begin
      Proc.Parameters.Add('-U');
      Proc.Parameters.Add(AUser);
      // password supplied below via SQLCMDPASSWORD
    end;
    Proc.Parameters.Add('-i'); Proc.Parameters.Add(ASqlFile);
    Proc.Parameters.Add('-f'); Proc.Parameters.Add('65001'); // UTF-8 in/out
    if ALoginTimeout >= 0 then
    begin
      Proc.Parameters.Add('-l'); Proc.Parameters.Add(IntToStr(ALoginTimeout));
    end;
    if AQueryTimeout >= 0 then
    begin
      Proc.Parameters.Add('-t'); Proc.Parameters.Add(IntToStr(AQueryTimeout));
    end;
    // No -b: sqlcmd continues past errors so every problem is reported in one run.

    if AWindowsAuth then
      PopulateProcEnv(Proc.Environment, '', '')
    else
      PopulateProcEnv(Proc.Environment, 'SQLCMDPASSWORD', APassword);

    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        AOutput := 'Could not launch sqlcmd (is it installed and on PATH?): ' + E.Message;
        Exit; // Result stays -2
      end;
    end;

    while Proc.Running do
    begin
      if Proc.Output.NumBytesAvailable > 0 then
      begin
        BytesRead := Proc.Output.Read(Buffer, SizeOf(Buffer));
        OutStream.Write(Buffer, BytesRead);
      end
      else
      begin
        Application.ProcessMessages; // keep UI alive and let Cancel be clicked
        if FCancelRequested then
        begin
          Proc.Terminate(1); // stop this database's sqlcmd
          Break;
        end;
        Sleep(10);
      end;
    end;
    while Proc.Output.NumBytesAvailable > 0 do
    begin
      BytesRead := Proc.Output.Read(Buffer, SizeOf(Buffer));
      OutStream.Write(Buffer, BytesRead);
    end;

    if OutStream.Size > 0 then
    begin
      SetLength(AOutput, OutStream.Size);
      Move(OutStream.Memory^, AOutput[1], OutStream.Size);
    end;
    Result := Proc.ExitStatus;
  finally
    Proc.Free;
    OutStream.Free;
  end;
end;

{ Counts SQL Server error messages in sqlcmd output. Counts "Msg N, Level L, ..."
  lines with a level >= 11 (levels 0-10 are informational) and any
  "Sqlcmd: Error" lines (connection/login failures). }
function TMainFrm.CountSqlErrors(const AOutput: string): Integer;
var
  Lines: TStringList;
  i, p, Level: Integer;
  L, LevelStr: string;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := AOutput;
    for i := 0 to Lines.Count - 1 do
    begin
      L := Lines[i];
      if Pos('Msg ', L) = 1 then
      begin
        p := Pos(', Level ', L);
        if p > 0 then
        begin
          LevelStr := Trim(Copy(L, p + Length(', Level '), 3));
          // keep only leading digits
          p := 1;
          while (p <= Length(LevelStr)) and (LevelStr[p] in ['0'..'9']) do
            Inc(p);
          LevelStr := Copy(LevelStr, 1, p - 1);
          Level := StrToIntDef(LevelStr, 0);
          if Level >= 11 then
            Inc(Result);
        end;
      end
      else if Pos('Sqlcmd: Error', L) > 0 then
        Inc(Result);
    end;
  finally
    Lines.Free;
  end;
end;

{ Heuristic: does the sqlcmd output look like a connection/network failure (worth
  retrying) rather than a plain T-SQL error (which a retry would not fix)? }
function TMainFrm.LooksLikeConnectivityFailure(const AOutput: string): Boolean;
const
  Markers: array[0..11] of string = (
    'communication link failure', 'login timeout', 'timeout expired',
    'network-related', 'named pipes provider', 'tcp provider',
    'server was not found', 'unable to complete login', 'transport-level error',
    'sqlcmd: error', 'shared memory provider', 'no connection could be made');
var
  LowOut: string;
  i: Integer;
begin
  Result := False;
  LowOut := LowerCase(AOutput);
  for i := 0 to High(Markers) do
    if Pos(Markers[i], LowOut) > 0 then
      Exit(True);
end;

{ Sleeps up to ASeconds while keeping the UI responsive and honouring Cancel. }
procedure TMainFrm.InterruptibleSleep(ASeconds: Integer);
var
  i: Integer;
begin
  for i := 1 to ASeconds * 20 do // 20 x 50ms = 1s
  begin
    if FCancelRequested then
      Exit;
    Application.ProcessMessages;
    Sleep(50);
  end;
end;

{ Requests cancellation of an in-progress run. }
procedure TMainFrm.CancelBtnClick(Sender: TObject);
begin
  if FRunning then
  begin
    FCancelRequested := True;
    RunLogMemo.Lines.Add('*** Cancel requested - stopping after the current database... ***');
  end;
end;

{ Runs the chosen SQL file against every database listed in the environment file's
  "Databases" field. Each database's result (OK / error count) is shown in the grid,
  and full output for any failed database is written to the log so it can be fixed
  and re-run. }
procedure TMainFrm.RunBtnClick(Sender: TObject);
var
  Server, User, Password, SqlFile, EnvFile, DatabasesCsv: string;
  Databases, ResList: TStringList;
  WinAuth, DidBackup, ConnFail, RunOk: Boolean;
  i, ExitCode, Errors, FailCount, BkIdx: Integer;
  LoginTO, QueryTO, Retries, RetryWait, Attempt, Processed: Integer;
  Db, Output, Status, LogBase, LogPath, ResPath: string;
begin
  if FRunning then
    Exit; // a run is already in progress
  Server := Trim(ServerEdt.Text);
  User := Trim(UserEdt.Text);
  Password := PasswordEdt.Text;
  SqlFile := Trim(RunSqlFileEdt.Text);
  EnvFile := Trim(RunEnvFileEdt.Text);
  WinAuth := WindowsAuthChk.Checked;

  if Server = '' then
  begin
    ShowMessage('Please enter the SQL Server (e.g. localhost\instance).');
    Exit;
  end;
  if (not WinAuth) and (User = '') then
  begin
    ShowMessage('Please enter a User (or tick Windows Authentication).');
    Exit;
  end;
  if (SqlFile = '') or not FileExists(SqlFile) then
  begin
    ShowMessage('Please enter a valid SQL File to run.');
    Exit;
  end;

  LoginTO := StrToIntDef(Trim(LoginTimeoutEdt.Text), 15);
  QueryTO := StrToIntDef(Trim(QueryTimeoutEdt.Text), 300);
  Retries := StrToIntDef(Trim(RetriesEdt.Text), 0);
  if Retries < 0 then Retries := 0;
  RetryWait := StrToIntDef(Trim(RetryWaitEdt.Text), 15);
  if RetryWait < 0 then RetryWait := 0;

  FRunning := True;
  FCancelRequested := False;
  RunBtn.Enabled := False;
  LoadFailedBtn.Enabled := False;
  ExportRunLogBtn.Enabled := False;
  CancelBtn.Enabled := True;

  Databases := TStringList.Create;
  try
    if OnlyFailedChk.Checked then
    begin
      // Re-run only the databases that failed on the previous run this session.
      if (FLastFailedDbs = nil) or (FLastFailedDbs.Count = 0) then
      begin
        ShowMessage('No failed databases are recorded yet in this session.' + sLineBreak +
          'Uncheck "Re-run failed only" and run all databases first.');
        Exit;
      end;
      Databases.Assign(FLastFailedDbs);
    end
    else
    begin
      if (EnvFile = '') or not FileExists(EnvFile) then
      begin
        ShowMessage('Please enter a valid Environment File (its "Databases" list is used).');
        Exit;
      end;
      DatabasesCsv := ReadJSONStringField(EnvFile, 'Databases');
      if Trim(DatabasesCsv) = '' then
      begin
        ShowMessage('The environment file has no "Databases" list: ' + EnvFile);
        Exit;
      end;
      Databases.Delimiter := ',';
      Databases.StrictDelimiter := True;
      Databases.DelimitedText := DatabasesCsv;
    end;

    // Set up results grid
    RunResultsGrid.ColCount := 3;
    RunResultsGrid.RowCount := 1;
    RunResultsGrid.Cells[0, 0] := 'Database';
    RunResultsGrid.Cells[1, 0] := 'Result';
    RunResultsGrid.Cells[2, 0] := 'Errors';

    RunLogMemo.Clear;
    RunLogMemo.Lines.Add('Running "' + SqlFile + '"');
    RunLogMemo.Lines.Add('Server: ' + Server + '   Auth: ' +
      IfThen(WinAuth, 'Windows', 'SQL (' + User + ')'));
    RunLogMemo.Lines.Add('Mode: ' + IfThen(OnlyFailedChk.Checked,
      Format('re-run failed only (%d database(s))', [Databases.Count]),
      Format('all databases (%d)', [Databases.Count])));
    RunLogMemo.Lines.Add('');

    RunProgressBar.Min := 0;
    RunProgressBar.Max := Databases.Count;
    RunProgressBar.Position := 0;

    FailCount := 0;

    for i := 0 to Databases.Count - 1 do
    begin
      Db := Trim(Databases[i]);
      if Db = '' then
      begin
        RunProgressBar.Position := i + 1;
        Continue;
      end;

      RunResultsGrid.RowCount := RunResultsGrid.RowCount + 1;
      if RunResultsGrid.RowCount > 1 then
        RunResultsGrid.FixedRows := 1;
      RunResultsGrid.Cells[0, RunResultsGrid.RowCount - 1] := Db;
      RunResultsGrid.Cells[1, RunResultsGrid.RowCount - 1] := 'running...';
      Application.ProcessMessages;

      Attempt := 0;
      repeat
        ExitCode := RunSqlcmd(Server, Db, User, Password, SqlFile, WinAuth,
          LoginTO, QueryTO, Output);
        Errors := CountSqlErrors(Output);
        RunOk := (Errors = 0) and (ExitCode = 0);
        if RunOk or FCancelRequested or (ExitCode = -2) then
          Break;
        // Only retry connection/network problems - a plain SQL error will just recur.
        ConnFail := (ExitCode <> 0) or LooksLikeConnectivityFailure(Output);
        if (not ConnFail) or (Attempt >= Retries) then
          Break;
        Inc(Attempt);
        RunLogMemo.Lines.Add(Format('%s: connection problem - retry %d of %d in %d s...',
          [Db, Attempt, Retries, RetryWait]));
        Application.ProcessMessages;
        InterruptibleSleep(RetryWait);
      until FCancelRequested;

      if RunOk then
        Status := 'OK'
      else
        Status := 'ERROR';

      RunResultsGrid.Cells[1, RunResultsGrid.RowCount - 1] := Status;
      RunResultsGrid.Cells[2, RunResultsGrid.RowCount - 1] := IntToStr(Errors);

      if Status = 'ERROR' then
      begin
        Inc(FailCount);
        RunLogMemo.Lines.Add('===================================================');
        RunLogMemo.Lines.Add('DATABASE: ' + Db + '  ->  ' + Status +
          ' (' + IntToStr(Errors) + ' error(s), exit ' + IntToStr(ExitCode) + ')');
        RunLogMemo.Lines.Add('---------------------------------------------------');
        RunLogMemo.Lines.Add(TrimRight(Output));
        RunLogMemo.Lines.Add('');
      end
      else
        RunLogMemo.Lines.Add(Db + '  ->  OK');

      RunProgressBar.Position := i + 1;
      Application.ProcessMessages;

      if FCancelRequested then
      begin
        RunLogMemo.Lines.Add('*** Run cancelled by user. ***');
        Break;
      end;
      if ExitCode = -2 then
      begin
        // sqlcmd could not be launched at all - stop, every DB would fail the same way.
        ShowMessage('sqlcmd could not be launched. Ensure the SQL Server command line ' +
          'tools are installed and sqlcmd is on the PATH.');
        Break;
      end;
    end;

    Processed := RunResultsGrid.RowCount - 1; // databases actually run (grid data rows)

    // Remember which databases failed so "Re-run failed only" can target them next.
    if FLastFailedDbs = nil then
      FLastFailedDbs := TStringList.Create;
    FLastFailedDbs.Clear;
    for i := 1 to RunResultsGrid.RowCount - 1 do
      if RunResultsGrid.Cells[1, i] = 'ERROR' then
        FLastFailedDbs.Add(RunResultsGrid.Cells[0, i]);

    RunLogMemo.Lines.Add('');
    RunLogMemo.Lines.Add(Format('Done: %d database(s) run, %d failed.%s',
      [Processed, FailCount,
       IfThen(FCancelRequested, ' (cancelled before finishing)', '')]));

    // Auto-save the run output into the release folder (next to the SQL file).
    LogPath := '';
    if Trim(SqlFile) <> '' then
    begin
      LogBase := IncludeTrailingPathDelimiter(ExtractFilePath(SqlFile)) +
        ChangeFileExt(ExtractFileName(SqlFile), '');
      LogPath := LogBase + '_RunLog.txt';
      ResPath := LogBase + '_RunResults.csv';
      try
        // Preserve the previous run's outputs (paired, same index) so the clean
        // "_RunResults.csv"/"_RunLog.txt" names always hold the latest run.
        DidBackup := False;
        BkIdx := 1;
        while FileExists(IndexedName(ResPath, BkIdx)) or
              FileExists(IndexedName(LogPath, BkIdx)) do
          Inc(BkIdx);
        if FileExists(ResPath) then
        begin
          RenameFile(ResPath, IndexedName(ResPath, BkIdx));
          DidBackup := True;
        end;
        if FileExists(LogPath) then
        begin
          RenameFile(LogPath, IndexedName(LogPath, BkIdx));
          DidBackup := True;
        end;
        if DidBackup then
          RunLogMemo.Lines.Add('Previous run backed up with suffix _' + IntToStr(BkIdx));

        ResList := TStringList.Create;
        try
          ResList.Add('Database,Result,Errors');
          for i := 1 to RunResultsGrid.RowCount - 1 do
            ResList.Add('"' + RunResultsGrid.Cells[0, i] + '","' +
              RunResultsGrid.Cells[1, i] + '","' + RunResultsGrid.Cells[2, i] + '"');
          ResList.SaveToFile(ResPath);
        finally
          ResList.Free;
        end;
        RunLogMemo.Lines.Add('Saved results: ' + ResPath);
        RunLogMemo.Lines.SaveToFile(LogPath); // save last so it includes the note above
        RunLogMemo.Lines.Add('Saved log: ' + LogPath);
      except
        on E: Exception do
          RunLogMemo.Lines.Add('Could not auto-save run output: ' + E.Message);
      end;
    end;

    ShowMessage(Format('%s on %d database(s).' + sLineBreak +
      '%d succeeded, %d failed.' + sLineBreak + '%s',
      [IfThen(FCancelRequested, 'Cancelled', 'Finished'), Processed,
       Processed - FailCount, FailCount,
       IfThen(LogPath <> '', 'Log + results saved next to the SQL file.',
         'See the log for details of any failures.')]));
  finally
    Databases.Free;
    FRunning := False;
    FCancelRequested := False;
    RunBtn.Enabled := True;
    LoadFailedBtn.Enabled := True;
    ExportRunLogBtn.Enabled := True;
    CancelBtn.Enabled := False;
  end;
end;

end.
