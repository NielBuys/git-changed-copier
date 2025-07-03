unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  Grids, Process, FileUtil, IniFiles;

type

  { TMainFrm }

  TMainFrm = class(TForm)
    ExportChangedFilesBtn: TButton;
    CopiedFilesStringGrid: TStringGrid;
    SaveDialog1: TSaveDialog;
    ToBaseFolderEdt: TEdit;
    CopyChangedFilesBtn: TButton;
    FromBaseFolderEdt: TEdit;
    FromBaseFolderLbl: TLabel;
    ProgressBar1: TProgressBar;
    ToGitTagLbl: TLabel;
    ToGitTagEdt: TEdit;
    FromTagEdt: TEdit;
    FiltersEdt: TEdit;
    FiltersLbl: TLabel;
    FromTagLbl: TLabel;
    BaseFolderLbl: TLabel;
    procedure CopyChangedFilesBtnClick(Sender: TObject);
    procedure ExportChangedFilesBtnClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
  private
    function FolderHasAnyFiles(const Dir: string): Boolean;
    function GetChangedSQLFilesFromTag(
      const FromGitTag, FromBasePath, FileFilter, ToBasePath, ToGitTag: string): TStringList;

  public

  end;

var
  MainFrm: TMainFrm;

implementation

{$R *.lfm}

{ TMainFrm }

procedure TMainFrm.CopyChangedFilesBtnClick(Sender: TObject);
var
  ChangedFiles: TStringList;
  i: Integer;
begin
  try
    ChangedFiles := GetChangedSQLFilesFromTag(
      FromTagEdt.Text,                     // FromGitTag: the tag to diff from
      FromBaseFolderEdt.Text,         // FromBasePath: path to Git repo
      FiltersEdt.Text,                      // FileFilter: only match .sql files
      ToBaseFolderEdt.Text,                // ToBasePath: root export location
      ToGitTagEdt.text              // ToGitTag: subfolder to create under ToBasePath
    );

    // Prepare the StringGrid
    CopiedFilesStringGrid.RowCount := ChangedFiles.Count + 1; // +1 for header
    CopiedFilesStringGrid.ColCount := 1;
    CopiedFilesStringGrid.Cells[0, 0] := 'Copied SQL Files'; // header
    CopiedFilesStringGrid.ColWidths[0] := 300; // Set column width
    CopiedFilesStringGrid.FixedRows := 1;

    // Fill the grid
    for i := 0 to ChangedFiles.Count - 1 do
    begin
      CopiedFilesStringGrid.Cells[0, i + 1] := ChangedFiles[i];
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
    finally
      Ini.Free;
    end;
  end;
end;

function TMainFrm.GetChangedSQLFilesFromTag(
  const FromGitTag, FromBasePath, FileFilter, ToBasePath, ToGitTag: string): TStringList;
var
  GitProcess: TProcess;
  OutputLines: TStringList;
  i, ProgressIndex: Integer;
  FileName, SrcFilePath, DestDir, DestFilePath, FilterExt: string;
  ValidFiles: TStringList;
  OutputStream: TMemoryStream;
  Buffer: array[0..2047] of byte;
  BytesRead: LongInt;
begin
  Result := TStringList.Create;
  OutputLines := TStringList.Create;
  ValidFiles := TStringList.Create;
  GitProcess := TProcess.Create(nil);
  OutputStream := TMemoryStream.Create;
  try
    // Set up destination directory
    DestDir := IncludeTrailingPathDelimiter(ToBasePath) + ToGitTag;

    // Check if destination folder exists and is not empty
    if DirectoryExists(DestDir) and FolderHasAnyFiles(DestDir) then
    begin
      Result.Free;
      OutputLines.Free;
      ValidFiles.Free;
      GitProcess.Free;
      OutputStream.Free;
      ShowMessage('Destination folder "' + DestDir + '" already exists and is not empty.');
      Exit;
    end;

    // Prepare Git process
    GitProcess.Executable := 'git';
    GitProcess.Options := [poUsePipes];
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

    // Normalize extension filter (e.g., '*.sql' → '.sql')
    FilterExt := LowerCase(ExtractFileExt(FileFilter));

    // First filter the relevant files
    for i := 0 to OutputLines.Count - 1 do
    begin
      FileName := Trim(OutputLines[i]);

      if (FilterExt = '') or (LowerCase(ExtractFileExt(FileName)) = FilterExt) then
        ValidFiles.Add(FileName);
    end;

    // Setup and reset ProgressBar
    ProgressBar1.Min := 0;
    ProgressBar1.Max := ValidFiles.Count;
    ProgressBar1.Position := 0;

    // Create destination directory
    ForceDirectories(DestDir);

    // Copy files with progress
    for ProgressIndex := 0 to ValidFiles.Count - 1 do
    begin
      FileName := ValidFiles[ProgressIndex];
      SrcFilePath := IncludeTrailingPathDelimiter(FromBasePath) + FileName;
      DestFilePath := IncludeTrailingPathDelimiter(DestDir) + FileName;

      ForceDirectories(ExtractFilePath(DestFilePath));

      if FileExists(SrcFilePath) then
      begin
        CopyFile(SrcFilePath, DestFilePath);
        Result.Add(FileName);
      end;

      // Update progress bar
      ProgressBar1.Position := ProgressIndex + 1;
      Application.ProcessMessages;
    end;

  finally
    GitProcess.Free;
    OutputLines.Free;
    ValidFiles.Free;
    OutputStream.Free;
  end;
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


end.

