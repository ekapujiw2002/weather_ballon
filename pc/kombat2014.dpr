program kombat2014;

uses
  Forms,
  uMain in 'uMain.pas' {frmMainKombat},
  chart_util in '..\..\lib\chart\chart_util.pas',
  gps_util in '..\..\lib\gps\gps_util.pas',
  uStrUtil in '..\..\lib\string-util\uStrUtil.pas',
  modbus_unit in '..\..\lib\modbus\modbus_unit.pas',
  string_conversion_unit in '..\..\lib\string-num-util\string_conversion_unit.pas',
  uHomePosition in 'uHomePosition.pas' {frmHomePosition};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'KOMBAT MDP';
  Application.CreateForm(TfrmMainKombat, frmMainKombat);
  Application.CreateForm(TfrmHomePosition, frmHomePosition);
  Application.Run;
end.
