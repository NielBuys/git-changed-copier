unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  Grids, Process, FileUtil, IniFiles, StrUtils, fpjson, jsonparser;

type

  { TMainFrm }

  TMainFrm = class(TForm)
    AddDependentFilesBtn: TButton;
    BaseFolderLbl: TLabel;
    CopiedFilesStringGrid: TStringGrid;
    CopyChangedFilesBtn: TButton;
    DependentSQLFoldersEdt: TEdit;
    DependentSQLFoldersLbl: TLabel;
    EnvFileEdt: TEdit;
    EnvFileLbl: TLabel;
    ExportChangedFilesBtn: TButton;
    FiltersEdt: TEdit;
    FiltersLbl: TLabel;
    FromBaseFolderEdt: TEdit;
    FromBaseFolderLbl: TLabel;
    FromTagEdt: TEdit;
    FromTagLbl: TLabel;
    GenerateBtn: TButton;
    GenerateSingleFileTab: TTabSheet;
    GenLogMemo: TMemo;
    GenProgressBar: TProgressBar;
    MainSQLFolderEdt: TEdit;
    MainSQLFolderLbl: TLabel;
    PageControl1: TPageControl;
    CopyChangedGitFilesTab: TTabSheet;
    PassesEdt: TEdit;
    PassesLbl: TLabel;
    ProgressBar1: TProgressBar;
    SaveDialog1: TSaveDialog;
    SqlRootEdt: TEdit;
    SqlRootLbl: TLabel;
    ToBaseFolderEdt: TEdit;
    ToGitTagEdt: TEdit;
    ToGitTagLbl: TLabel;
    procedure AddDependentFilesBtnClick(Sender: TObject);
    procedure CopyChangedFilesBtnClick(Sender: TObject);
    procedure ExportChangedFilesBtnClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure GenerateBtnClick(Sender: TObject);
  private
    function FolderHasAnyFiles(const Dir: string): Boolean;
    function ReadJSONStringField(const AFileName, AField: string): string;
    procedure StreamWriteText(AStream: TStream; const AText: string);
    procedure StreamAppendFile(AStream: TStream; const AFileName: string);
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
    Ini.WriteString('Settings', 'SqlRoot', SqlRootEdt.Text);
    Ini.WriteString('Settings', 'EnvFile', EnvFileEdt.Text);
    Ini.WriteString('Settings', 'Passes', PassesEdt.Text);
  finally
    Ini.Free;
  end;
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
      SqlRootEdt.Text := Ini.ReadString('Settings', 'SqlRoot', '');
      EnvFileEdt.Text := Ini.ReadString('Settings', 'EnvFile', '');
      PassesEdt.Text := Ini.ReadString('Settings', 'Passes', '1');
    finally
      Ini.Free;
    end;
  end;
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

{ Appends the raw bytes of a file to a stream (preserves original encoding). }
procedure TMainFrm.StreamAppendFile(AStream: TStream; const AFileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    if FS.Size > 0 then
      AStream.CopyFrom(FS, FS.Size);
  finally
    FS.Free;
  end;
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
  SqlRoot := Trim(SqlRootEdt.Text);
  EnvFile := Trim(EnvFileEdt.Text);

  if (SqlRoot = '') or not DirectoryExists(SqlRoot) then
  begin
    ShowMessage('Please enter a valid SQL Folder (the folder containing the module ' +
      'sub-folders, e.g. ...\SQL).');
    Exit;
  end;
  if (EnvFile = '') or not FileExists(EnvFile) then
  begin
    ShowMessage('Please enter a valid Environment File ' +
      '(e.g. C:\Development\SQLUpdate\Config\WineMS2.json).');
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

  // Ask where to save the generated file.
  SaveDialog1.Title := 'Save Generated SQL File';
  SaveDialog1.DefaultExt := 'sql';
  SaveDialog1.Filter := 'SQL Files (*.sql)|*.sql|All Files (*.*)|*.*';
  SaveDialog1.FileName := EnvName + '.sql';
  if not SaveDialog1.Execute then
    Exit;

  GenLogMemo.Clear;
  ScriptNames := TStringList.Create;
  Folders := TStringList.Create;
  OutStream := TFileStream.Create(SaveDialog1.FileName, fmCreate);
  try
    // File header
    StreamWriteText(OutStream,
      '-- Generated single SQL file for environment: ' + EnvName + sLineBreak +
      '-- Target databases: ' + Databases + sLineBreak +
      '-- Scripts (order): ' + ScriptsCsv + sLineBreak +
      '-- Generated: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + sLineBreak +
      '-- Passes: ' + IntToStr(Passes) + sLineBreak +
      'GO' + sLineBreak);

    GenLogMemo.Lines.Add('Environment : ' + EnvName);
    GenLogMemo.Lines.Add('Databases   : ' + Databases);
    GenLogMemo.Lines.Add('Scripts     : ' + ScriptsCsv);
    GenLogMemo.Lines.Add('Passes      : ' + IntToStr(Passes));
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
      [IncludedPerPass, Passes, SaveDialog1.FileName]));
    ShowMessage(Format('Generated single SQL file:' + sLineBreak + '%s' + sLineBreak +
      sLineBreak + '%d file(s) per pass, %d pass(es).',
      [SaveDialog1.FileName, IncludedPerPass, Passes]));
  finally
    OutStream.Free;
    ScriptNames.Free;
    Folders.Free;
  end;
end;

end.
