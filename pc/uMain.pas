unit uMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ImgList, CPort, ExtCtrls, TeEngine, Series, TeeProcs,
  Chart, StdCtrls, Buttons, CnHint, IniFiles,

  gps_util,
  chart_util,
  string_conversion_unit,
  modbus_unit,
  uStrUtil,

  _GClass, AbCompas, BMDThread,

  uHomePosition, IAgaloLED, Spin;

type
  //record data acq
  TDataAcq = packed record
    isRunning: Boolean;
    bufferDataReceived: string;
    lastTickms: Cardinal;
    updateInterval: Cardinal;
  end;

  //data payload record
  TPayloadData = packed record
    isValid: Boolean;
    IDDevice: Byte;
    CommandCode: Byte;
    DataLength: Byte;
    DataPayload: string;
    CRC16: Word;
  end;

  //data payload content
  TPayloadContent = packed record
    //current pos
    GPSStatus: Byte;
    GPSLat, GPSLon, GPSAltitude: Real;
    GPSTimeStamp: Cardinal;
    GPSSpeed: Real;

    //last pos
    GPSLastLat, GPSLastLon, GPSLastAltitude, BearingFromLastPos: Real;
    GPSLastTimeStamp: Cardinal;

    //home position
    GPSHomeLat, GPSHomeLon, GPSHomeAltitude, BearingFromHome, DistanceFromHome:
    Real;

    //bmp data
    BMPPressure, BMPTemperature, BMPAltitude,

    //humidity
    DHTHumidity,

    //calc speed
    CalculatedGroundSpeed,

    //power level
    PowerLevel: Real;
  end;

  TfrmMainKombat = class(TForm)
    statbarMain: TStatusBar;
    pgcMain: TPageControl;
    tsChart: TTabSheet;
    tsConfiguration: TTabSheet;
    imglstMain: TImageList;
    comportMainKombat: TComPort;
    cmdtpcktMainKombat: TComDataPacket;
    pnlChartMain: TPanel;
    pnlChartToolbar: TPanel;
    pnlChartTop: TPanel;
    chtTekanan: TChart;
    fstlnsrsTekanan: TFastLineSeries;
    chtSuhu: TChart;
    fstlnsrsSuhu: TFastLineSeries;
    pnlChartBottom: TPanel;
    chtRH: TChart;
    fstlnsrsRH: TFastLineSeries;
    chtWindSpeed: TChart;
    fstlnsrsWindSpeed: TFastLineSeries;
    btnStartStop: TBitBtn;
    cnhntMain: TCnHint;
    btnConnectDisconnect: TBitBtn;
    pnlWindDirection: TPanel;
    abcmpsWind: TAbCompass;
    btnClearChart: TBitBtn;
    btnConfigPort: TBitBtn;
    bmdthrdMain: TBMDThread;
    tmrMain: TTimer;
    imglstToolbar: TImageList;
    btnTesChart: TButton;
    btnSetHomePosition: TBitBtn;
    lvLastInfo: TListView;
    tsDataLog: TTabSheet;
    grpDataLogToolbar: TGroupBox;
    lvDataLog: TListView;
    igldGPSFix: TIAgaloLED;
    pbPowerLeve: TProgressBar;
    lbl1: TLabel;
    seConfigCmdPollTime: TSpinEdit;
    lbl2: TLabel;
    seConfigCmdTimeout: TSpinEdit;
    btnConfigSave: TBitBtn;
    procedure FormResize(Sender: TObject);
    procedure btnStartStopClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnConfigPortClick(Sender: TObject);
    procedure ThreadDataAcquisition(Sender: TObject);
    procedure bmdthrdMainExecute(Sender: TObject;
      Thread: TBMDExecuteThread; var Data: Pointer);
    procedure tmrMainTimer(Sender: TObject);
    procedure bmdthrdMainStart(Sender: TObject; Thread: TBMDExecuteThread;
      var Data: Pointer);
    procedure bmdthrdMainTerminate(Sender: TObject;
      Thread: TBMDExecuteThread; var Data: Pointer);
    procedure btnConnectDisconnectClick(Sender: TObject);
    procedure comportMainKombatAfterClose(Sender: TObject);
    procedure comportMainKombatAfterOpen(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnClearChartClick(Sender: TObject);
    procedure btnTesChartClick(Sender: TObject);
    procedure lvDataLogInsert(Sender: TObject; Item: TListItem);
    procedure btnSetHomePositionClick(Sender: TObject);
    procedure btnConfigSaveClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmMainKombat: TfrmMainKombat;

  //var utk data acq thread
  payloadDataAcq: TDataAcq;
  payloadDataReceived: TPayloadData;
  payloadDataContent: TPayloadContent;

  //var datalog
  fLogName: string;

const
  SampelDataPressureAltitude: array[1..30, 1..2] of Real = (
    (0, 101.33),
    (153, 99.49),
    (305, 97.63),
    (458, 95.91),
    (610, 94.19),
    (763, 92.46),
    (915, 90.81),
    (1068, 89.15),
    (1220, 87.49),
    (1373, 85.91),
    (1526, 84.33),
    (1831, 81.22),
    (2136, 78.19),
    (2441, 75.22),
    (2746, 72.4),
    (3050, 69.64),
    (4577, 57.16),
    (6102, 46.61),
    (7628, 37.65),
    (9153, 30.13),
    (10679, 23.93),
    (12204, 18.82),
    (13730, 14.82),
    (15255, 11.65),
    (16781, 9.17),
    (18306, 7.24),
    (21357, 4.49),
    (24408, 2.8),
    (27459, 1.76),
    (30510, 1.12)
    );

implementation

{$R *.dfm}

{*--------------------------------------------------------------------
format data command sesuai modbus

@author
@version
----------------------------------------------------------------------}

function FormatCommand(aIDTarget: Byte; aCommandID: Byte; aPayloadDataLength:
  Byte; aPayloadData: string): string;
var
  cmdx: string;
  crcx: Word;
begin
  try
    cmdx := chr(aIDTarget) + chr(aCommandID) + chr(aPayloadDataLength) +
      aPayloadData;
    crcx := modbus_crc(cmdx);
    cmdx := cmdx + chr(crcx shr 8) + chr(crcx and $00FF);
  except
    cmdx := '';
  end;
  Result := cmdx;
end;

{*--------------------------------------------------------------------
fungsi utk kirim perintah ke comport dan tggu sampai timeout ato ada data masuk (sinkronus rx)
true -> tidak timeout
false -> timeout

@author
@version
----------------------------------------------------------------------}

function SendCommandWaitRespons(var data_rx: string; acmd: string; acom:
  TComPort; timeout_val: integer): boolean;
var
  cnt_timeout: integer;
  rx_chr: string;
begin
  data_rx := '';
  if acom.Connected then
  begin
    if acmd <> '' then
      acom.WriteStr(acmd); //kirim perintah

    cnt_timeout := 0; //reset counter timeout
    repeat
      inc(cnt_timeout);
      sleep(0);
      Application.ProcessMessages;
    until (acom.ReadStr(rx_chr, 1) > 0) or (cnt_timeout > (timeout_val / 10));
    //tggu sampai ada data masuk ato timeout

    if (cnt_timeout <= (timeout_val / 10)) then
      //jika tdk timeout -> ambil data selanjutnya
    begin
      data_rx := rx_chr;
      while acom.ReadStr(rx_chr, 1) > 0 do //ambil data masuk
        data_rx := data_rx + rx_chr;
      Result := true;
    end
    else //timeout -> set ke timeout
    begin
      data_rx := '';
      Result := false;
    end;
  end
  else
    Result := false;
end;

{*--------------------------------------------------------------------
parsing data from payload balon
payload data is little endian
@author
@version
----------------------------------------------------------------------}

function ProcessPayloadReceivedData(
  aIDDeviceTarget: Byte;
  aData: string;
  var aPayloadData: TPayloadData): Boolean;
var
  crcx, crcy: Word;
  strContent: string;
begin
  try
    aPayloadData.isValid := (aIDDeviceTarget = ord(adata[1])) and
      //id target check
//(aCmdSent = ord(adata[2])) and //cmd reply check
    (Length(aData) = (Ord(adata[3]) + 5)); //total data receive check
    //check is it for me?
    if aPayloadData.isValid then
    begin
      crcx := modbus_crc(Copy(aData, 1, (Ord(adata[3]) + 3)));
      //      crcx := ord(adata[(Ord(adata[3]) + 4)]) * 256 + ord(adata[(Ord(adata[3]) +
      //5)]);
      crcy := (ord(adata[(Ord(adata[3]) + 5)]) * 256 +
        ord(adata[(Ord(adata[3]) +
          4)]));
      aPayloadData.isValid := crcx = crcy;
      //check crc validity
      if aPayloadData.isValid then
      begin
        strContent := Copy(aData, 4, Ord(adata[3]));
        with aPayloadData do
        begin
          IDDevice := ord(adata[1]);
          CommandCode := Ord(adata[2]);
          DataLength := Ord(adata[3]);
          DataPayload := strContent;
          CRC16 := crcx;
        end;
      end;
    end;

    Result := aPayloadData.isValid;
  except
    Result := False;
  end;
end;

{*--------------------------------------------------------------------
parse data content

@author
@version
----------------------------------------------------------------------}

function ProcessPayloadDataReply(strContent: string; var aPayloadContent:
  TPayloadContent): Boolean;
var
  idData: Integer;
  distLast: Real;
  timeIntervalLast: Cardinal;
begin
  try
    with aPayloadContent do
    begin
      //update last post
      GPSLastLat := GPSLat;
      GPSLastLon := GPSLon;
      GPSLastAltitude := GPSAltitude;
      GPSLastTimeStamp := GPSTimeStamp;

      idData := 1;
      //gps status
      GPSStatus := ord(strContent[idData]);

      //gps lat
      idData := 2;
      GPSLat := (ord(strContent[idData + 3]) shl 24 +
        ord(strContent[idData + 2]) shl 16 +
        ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E7;

      //gps lon
      idData := 6;
      GPSLon := (ord(strContent[idData + 3]) shl 24 +
        ord(strContent[idData + 2]) shl 16 +
        ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E7;

      {
      GPSAltitude := (
        ord(strContent[10]) shl 8 +
        ord(strContent[11]));
}
      //timestamp
      idData := 10;
      GPSTimeStamp := (ord(strContent[idData + 3]) shl 24 +
        ord(strContent[idData + 2]) shl 16 +
        ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0]));

      //speed
      idData := 14;
      GPSSpeed := (ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0]));

      //pressure
      idData := 16;
      BMPPressure := (ord(strContent[idData + 3]) shl 24 +
        ord(strContent[idData + 2]) shl 16 +
        ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E3;

      //temperature
      idData := 20;
      BMPTemperature := (ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E2;

      //altitude
      idData := 22;
      BMPAltitude := (ord(strContent[idData + 3]) shl 24 +
        ord(strContent[idData + 2]) shl 16 +
        ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E2;

      //humidity
      idData := 26;
      DHTHumidity := (ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E2;

      //power level
      idData := 28;
      PowerLevel := (ord(strContent[idData + 1]) shl 8 +
        ord(strContent[idData + 0])) / 1E1;

      //calc bearing
      BearingFromHome :=
        GPS_Calc_Bearing(GPSHomeLat,
        GPSHomeLon,
        GPSLat, GPSLon);
      BearingFromLastPos := GPS_Calc_Bearing(
        GPSLastLat,
        GPSLastLon,
        GPSLat, GPSLon);
      DistanceFromHome := GPS_Calc_Distance(GPSHomeLat, GPSHomeLon, GPSLat,
        GPSLon);

      //calc speed in m/s
      //dist in m
      distLast := GPS_Calc_Distance(GPSLastLat, GPSLastLon, GPSLat, GPSLon) *
        1000;
      timeIntervalLast := (GPSTimeStamp - GPSLastTimeStamp);
      if timeIntervalLast > 0 then
        CalculatedGroundSpeed := distLast / (timeIntervalLast / 1000)
      else
        CalculatedGroundSpeed := 0;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

{*--------------------------------------------------------------------
set column listview caption

@author
@version
----------------------------------------------------------------------}

procedure SetListViewColumnCaption(aListView: TListView; const arrCol: array of
  string; const
  arrWidth: array of Integer);
var
  i: Integer;
begin
  aListView.Columns.Clear;
  for i := Low(arrCol) to High(arrCol) do
  begin
    with aListView.Columns.Add do
    begin
      Caption := arrCol[i];
      AutoSize := True;
      MinWidth := arrWidth[i];
      Width := arrWidth[i];
    end;
  end;
end;

{*--------------------------------------------------------------------
add data to listview

@author
@version
----------------------------------------------------------------------}

procedure AddLastFlightInfoData(aLV: TListView;
  aAltitude, lat, lon, wind_speed, wind_bearing: Real;
  tstamp: Cardinal;
  pressure, temperature, humidity: Real;
  home_lat, home_lon, home_altitude, home_distance, home_bearing: Real;
  const isOnly1Data: Boolean = True
  );
begin
  try
    with aLV do
    begin
      if isOnly1Data then
      begin
        if Items[0] = nil then
        begin
          with Items.Add do
          begin
            Caption := FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', Now);
            SubItems.Add(FormatFloat('#0.000', aAltitude));
            SubItems.Add(FormatFloat('#0.0000000', lat));
            SubItems.Add(FormatFloat('#0.0000000', lon));
            SubItems.Add(FormatFloat('#0.000', wind_speed));
            SubItems.Add(FormatFloat('#0.000', wind_bearing));
            SubItems.Add(IntToStr(tstamp));
            SubItems.Add(FormatFloat('#0.000', pressure));
            SubItems.Add(FormatFloat('#0.0', temperature));
            SubItems.Add(FormatFloat('#0.0', humidity));
            SubItems.Add(FormatFloat('#0.0000000', home_lat));
            SubItems.Add(FormatFloat('#0.0000000', home_lon));
            SubItems.Add(FormatFloat('#0.000', home_altitude));
            SubItems.Add(FormatFloat('#0.00', home_distance));
            SubItems.Add(FormatFloat('#0.000', home_bearing));
          end;
        end
        else
        begin
          with Items[0] do
          begin
            Caption := FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', Now);
            SubItems.Strings[0] := FormatFloat('#0.000', aAltitude);
            SubItems.Strings[1] := FormatFloat('#0.0000000', lat);
            SubItems.Strings[2] := FormatFloat('#0.0000000', lon);
            SubItems.Strings[3] := FormatFloat('#0.000', wind_speed);
            SubItems.Strings[4] := FormatFloat('#0.000', wind_bearing);
            SubItems.Strings[5] := IntToStr(tstamp);
            SubItems.Strings[6] := FormatFloat('#0.000', pressure);
            SubItems.Strings[7] := FormatFloat('#0.0', temperature);
            SubItems.Strings[8] := FormatFloat('#0.0', humidity);
            SubItems.Strings[9] := FormatFloat('#0.0000000', home_lat);
            SubItems.Strings[10] := FormatFloat('#0.0000000', home_lon);
            SubItems.Strings[11] := FormatFloat('#0.000', home_altitude);
            SubItems.Strings[12] := FormatFloat('#0.00', home_distance);
            SubItems.Strings[13] := FormatFloat('#0.000', home_bearing);
          end;
        end;
      end
      else
      begin
        with Items.Add do
        begin
          Caption := FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', Now);
          SubItems.Add(FormatFloat('#0.000', aAltitude));
          SubItems.Add(FormatFloat('#0.0000000', lat));
          SubItems.Add(FormatFloat('#0.0000000', lon));
          SubItems.Add(FormatFloat('#0.000', wind_speed));
          SubItems.Add(FormatFloat('#0.000', wind_bearing));
          SubItems.Add(IntToStr(tstamp));
          SubItems.Add(FormatFloat('#0.000', pressure));
          SubItems.Add(FormatFloat('#0.0', temperature));
          SubItems.Add(FormatFloat('#0.0', humidity));
          SubItems.Add(FormatFloat('#0.0000000', home_lat));
          SubItems.Add(FormatFloat('#0.0000000', home_lon));
          SubItems.Add(FormatFloat('#0.000', home_altitude));
          SubItems.Add(FormatFloat('#0.00', home_distance));
          SubItems.Add(FormatFloat('#0.000', home_bearing));
        end;
      end;
    end;
  except

  end;
end;

{*--------------------------------------------------------------------
update glyph button

@author
@version
----------------------------------------------------------------------}

{
procedure UpdateGlyphImage(aGlyph: TBitmap; aImgList: TImageList; const
  aImgIndex: Integer = 0);
begin
  try
    aGlyph := nil;
    aImgList.GetBitmap(aImgIndex, aGlyph);
  except

  end;
end;
}

{*--------------------------------------------------------------------
log data ke file

@author
@version
----------------------------------------------------------------------}

procedure LogData2File(afile, adata: string; const isAdded: Boolean = True);
var
  lstx: TStringList;
begin
  try
    lstx := TStringList.Create;
    if FileExists(afile) and isAdded then
      lstx.LoadFromFile(afile);
    lstx.Add(adata);
    lstx.SaveToFile(afile);
    FreeAndNil(lstx);
  except
    begin
      FreeAndNil(lstx);
      //      Exit;
    end;
  end;
end;

//==============================================================================

procedure TfrmMainKombat.FormResize(Sender: TObject);
begin
  try
    pnlChartTop.Height := pnlChartMain.Height div 2;
    chtTekanan.Width := pnlChartTop.Width div 2;
    chtRH.Width := chtTekanan.Width;
  except

  end;
end;

procedure TfrmMainKombat.btnStartStopClick(Sender: TObject);
begin
  //ChartReset(chtTekanan);
  ////ChartInit(chtTekanan,'','TEKANAN');
  //ChartPlotValue(chtTekanan,fstlnsrsTekanan,1,100,'1',clDefault);
  //ChartPlotValue(chtTekanan,fstlnsrsTekanan,2.5,150,'2.5',clDefault);
  //ChartPlotValue(chtTekanan,fstlnsrsTekanan,3.1,200,'3.1',clDefault);
  //ChartPlotValue(chtTekanan,fstlnsrsTekanan,2.5,150,'2.5',clDefault);
  //ChartPlotValue(chtTekanan,fstlnsrsTekanan,1,100,'1',clDefault);
  //Sleep(1000);
  //ChartReset(chtTekanan);
//  imglstMain.GetBitmap(5, btnStartStop.Glyph);

  if comportMainKombat.Connected then
  begin
    if not bmdthrdMain.Runing then
    begin
      bmdthrdMain.Start;
      fLogName := FormatDateTime('dd-mm-yyyy-hh-nn-ss', Now) + '.log';
      LogData2File(IncludeTrailingPathDelimiter(Path + 'log\' +
        FormatDateTime('yyyy\mm\dd', Now)) + fLogName,
        'Time,Altitude(m),Lat('#176'),Lon('#176'),Timestamp,Wind Bearing('#176'),Wind Speed(m/s),Pressure(Pa),Temperature('#176'C), Humidity(%RH)' +
        'Home Latitude('#176'),Home Longitude('#176'),Home Altitude(m),Distance From Home(m),Bearing From Home('#176')'
        , False);
    end
    else
      bmdthrdMain.Stop;
  end;

end;

procedure TfrmMainKombat.FormCreate(Sender: TObject);
begin
  try
    //reset chart
    ChartReset(chtTekanan);
    ChartReset(chtSuhu);
    ChartReset(chtRH);
    ChartReset(chtWindSpeed);

    //assign icon
    imglstToolbar.GetBitmap(1, btnConnectDisconnect.Glyph);
    imglstToolbar.GetBitmap(2, btnConfigPort.Glyph);
    imglstToolbar.GetBitmap(3, btnStartStop.Glyph);
    imglstToolbar.GetBitmap(5, btnClearChart.Glyph);
    imglstToolbar.GetBitmap(6, btnSetHomePosition.Glyph);

    //init data
    with payloadDataAcq do
    begin
      isRunning := False;
      bufferDataReceived := '';
      lastTickms := GetTickCount;
      updateInterval := 5000;
    end;

    //reload config port
    comportMainKombat.LoadSettings(stIniFile, Path + 'balon_cfg.ini');

    //init home position
    with TIniFile.Create(Path + 'balon_cfg.ini') do
    begin
      payloadDataContent.GPSHomeLat := ReadFloat('home', 'lat', 0);
      payloadDataContent.GPSHomeLon := ReadFloat('home', 'lon', 0);
      payloadDataContent.GPSHomeAltitude := ReadFloat('home', 'altitude', 0);
      Free;
    end;

    //set listview info columns
    SetListViewColumnCaption(
      lvLastInfo,
      [
      'Time',
        'Altitude(m)',
        'Latitude('#176')',
        'Longitude('#176')',
        'Wind Speed(m/s)',
        'Wind Bearing('#176')',
        'Timestamp(ms)',
        'Pressure(kPa)',
        'Temperature('#176'C)',
        'Humidity(%RH)',
        'Home Latitude('#176')',
        'Home Longitude('#176')',
        'Home Altitude(m)',
        'Distance From Home(km)',
        'Bearing From Home('#176')'
        ],
        [
      140,
        100,
        150,
        150,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100
        ]
        );

    AddLastFlightInfoData(lvLastInfo, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      payloadDataContent.GPSHomeLat, payloadDataContent.GPSHomeLon,
      payloadDataContent.GPSHomeAltitude, 0, 0);

    SetListViewColumnCaption(
      lvDataLog,
      [
      'Time',
        'Altitude(m)',
        'Latitude('#176')',
        'Longitude('#176')',
        'Wind Speed(m/s)',
        'Wind Bearing('#176')',
        'Timestamp(ms)',
        'Pressure(kPa)',
        'Temperature('#176'C)',
        'Humidity(%RH)',
        'Home Latitude('#176')',
        'Home Longitude('#176')',
        'Home Altitude(m)',
        'Distance From Home(km)',
        'Bearing From Home('#176')'
        ],
        [
      120,
        100,
        150,
        150,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100
        ]
        );

    fLogName := FormatDateTime('dd-mm-yyyy-hh-nn-ss', Now) + '.log';

    //create log dir
    ForceDirectories(IncludeTrailingPathDelimiter(Path + 'log\' +
      FormatDateTime('yyyy\mm\dd', Now)));

    //hint pwr level
    pbPowerLeve.Hint := Format('Power = %.1f%%',
      [payloadDataContent.PowerLevel]);

    //load config file
    with TIniFile.Create(Path + 'balon_cfg.ini') do
    begin
      //time set
      seConfigCmdPollTime.Value := ReadInteger('time', 'poll interval', 5);
      seConfigCmdTimeout.Value := ReadInteger('time', 'reply timeout', 2);
    end;

  except
    on e: Exception do
    begin
      if MessageDlg('Error at :'#13 + e.Message + #13'Continue?', mtError,
        [mbYes, mbNo], MB_ICONERROR) <> mryes then
      begin
        Application.Terminate;
      end;
    end;
  end;
end;

procedure TfrmMainKombat.btnConfigPortClick(Sender: TObject);
begin
  try
    comportMainKombat.ShowSetupDialog;
    if MessageDlg(#13'Save setting?', mtConfirmation, [mbYes, mbNo],
      MB_ICONQUESTION) = mryes then
      comportMainKombat.StoreSettings(stIniFile, Path + 'balon_cfg.ini');
  except
    on e: Exception do
      MessageDlg('Error at : '#13 + e.Message, mtError, [mbOK],
        MB_ICONERROR);
  end;
end;

procedure TfrmMainKombat.ThreadDataAcquisition(Sender: TObject);
var
  bearing: Real;
begin
  try
    //    lbl1.Caption := FormatDateTime('hh:nn:ss.zzz', Now);
    if (not payloadDataAcq.isRunning) and ((GetTickCount -
      payloadDataAcq.lastTickms) >= payloadDataAcq.updateInterval) then
    begin
      payloadDataAcq.isRunning := True;
      payloadDataAcq.lastTickms := GetTickCount;

      //grab data
      if SendCommandWaitRespons(
        payloadDataAcq.bufferDataReceived,
        FormatCommand(1, 1, 0, ''),
        comportMainKombat,
        seConfigCmdTimeout.Value * 1000) then
      begin
        if payloadDataAcq.bufferDataReceived <> '' then
        begin
          //          lbl1.Caption := FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', Now) + ' : '
          //            +
          //            ascii2hex_simple(payloadDataAcq.bufferDataReceived, ' ');

                    //process received data
          if ProcessPayloadReceivedData(0,
            payloadDataAcq.bufferDataReceived,
            payloadDataReceived) then
          begin
            statbarMain.Panels[2].Text := 'Start processing content reply';

            case payloadDataReceived.CommandCode of
              1:
                begin
                  if ProcessPayloadDataReply(payloadDataReceived.DataPayload,
                    payloadDataContent) then
                  begin
                    //                    lbl1.Caption := FormatFloat('#0.000 m',payloadDataContent.BMPAltitude)+' = '+
                    //                      FormatFloat('#0.000 Pa',payloadDataContent.BMPPressure);

                                        //plot data
                    ChartPlotValue(chtTekanan, fstlnsrsTekanan,
                      payloadDataContent.BMPPressure,
                      payloadDataContent.BMPAltitude,
                      FormatFloat('#0.000', payloadDataContent.BMPPressure),
                      clDefault);

                    //                    fstlnsrsTekanan.Add(payloadDataContent.BMPAltitude, FormatFloat('#0.000',payloadDataContent.BMPPressure), clDefault);

                    ChartPlotValue(chtSuhu, fstlnsrsSuhu,
                      payloadDataContent.BMPTemperature,
                      payloadDataContent.BMPAltitude,
                      FormatFloat('#0.00', payloadDataContent.BMPTemperature),
                      clDefault);
                    ChartPlotValue(chtRH, fstlnsrsRH,
                      payloadDataContent.DHTHumidity,
                      payloadDataContent.BMPAltitude,
                      FormatFloat('#0.00', payloadDataContent.DHTHumidity),
                      clDefault);
                    ChartPlotValue(chtWindSpeed, fstlnsrsWindSpeed,
                      //                      payloadDataContent.GPSSpeed,
                      payloadDataContent.CalculatedGroundSpeed,
                      payloadDataContent.BMPAltitude,
                      FormatFloat('#0.00',
                      payloadDataContent.CalculatedGroundSpeed),
                      clDefault);

                    //draw angle
                    abcmpsWind.Value := payloadDataContent.BearingFromLastPos;
                    abcmpsWind.ValueShould := abcmpsWind.Value;

                    //update last data info
                    AddLastFlightInfoData(lvLastInfo,
                      payloadDataContent.BMPAltitude, payloadDataContent.GPSLat,
                      payloadDataContent.GPSLon,
                      //payloadDataContent.GPSSpeed,
                      payloadDataContent.CalculatedGroundSpeed,
                      payloadDataContent.BearingFromLastPos,
                      payloadDataContent.GPSTimeStamp,
                      payloadDataContent.BMPPressure,
                      payloadDataContent.BMPTemperature,
                      payloadDataContent.DHTHumidity,
                      payloadDataContent.GPSHomeLat,
                      payloadDataContent.GPSHomeLon,
                      payloadDataContent.GPSHomeAltitude,
                      payloadDataContent.DistanceFromHome,
                      payloadDataContent.BearingFromHome);

                    AddLastFlightInfoData(lvDataLog,
                      payloadDataContent.BMPAltitude, payloadDataContent.GPSLat,
                      payloadDataContent.GPSLon,
                      //payloadDataContent.GPSSpeed,
                      payloadDataContent.CalculatedGroundSpeed,
                      payloadDataContent.BearingFromLastPos,
                      payloadDataContent.GPSTimeStamp,
                      payloadDataContent.BMPPressure,
                      payloadDataContent.BMPTemperature,
                      payloadDataContent.DHTHumidity,
                      payloadDataContent.GPSHomeLat,
                      payloadDataContent.GPSHomeLon,
                      payloadDataContent.GPSHomeAltitude,
                      payloadDataContent.DistanceFromHome,
                      payloadDataContent.BearingFromHome,
                      False);

                    //fix status
                    igldGPSFix.LedOn := (payloadDataContent.GPSStatus and $06)
                      <> 0;

                    //power level gauge
                    pbPowerLeve.Position :=
                      Round(payloadDataContent.PowerLevel);

                    LogData2File(
                      IncludeTrailingPathDelimiter(Path + 'log\' +
                      FormatDateTime('yyyy\mm\dd', Now)) + fLogName,
                      Format(
                      FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', Now) + ',' +
                      //alt, lat, lon, timestamp, wind bearing, wind speed, pressure, temp, humidity
                      '%.3f,%.7f,%.7f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f'
                      ,
                      [
                      payloadDataContent.BMPAltitude,
                        payloadDataContent.GPSLat,
                        payloadDataContent.GPSLon,
                        payloadDataContent.GPSTimeStamp,
                        payloadDataContent.BearingFromLastPos,
                        //payloadDataContent.GPSSpeed,
                      payloadDataContent.CalculatedGroundSpeed,
                        payloadDataContent.BMPPressure,
                        payloadDataContent.BMPTemperature,
                        payloadDataContent.DHTHumidity,
                        payloadDataContent.GPSHomeLat,
                        payloadDataContent.GPSHomeLon,
                        payloadDataContent.GPSHomeAltitude,
                        payloadDataContent.DistanceFromHome,
                        payloadDataContent.BearingFromHome
                        ]
                        )
                      );

                    //hint pwr level
                    pbPowerLeve.Hint := Format('Power = %.1f%%',
                      [payloadDataContent.PowerLevel]);
                  end
                  else
                  begin
                    statbarMain.Panels[2].Text := 'Error parsing data';
                  end;
                end;
            else
              statbarMain.Panels[2].Text := 'Command unknown';
            end;
          end
          else
          begin
            statbarMain.Panels[2].Text := 'Cannot process content reply';
          end;
        end;
      end
      else
      begin
        statbarMain.Panels[2].Text := FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz',
          Now) +
          ' : Payload not responding...';
      end;

      payloadDataAcq.isRunning := False;
    end;
  except

  end;

  Application.ProcessMessages;
end;

procedure TfrmMainKombat.bmdthrdMainExecute(Sender: TObject;
  Thread: TBMDExecuteThread; var Data: Pointer);
begin
  try
    while (not Thread.Terminated) and (comportMainKombat.Connected) do
    begin
      Thread.Synchronize(ThreadDataAcquisition);
      SleepEx(50, True);
    end;
  except

  end;

  if bmdthrdMain.Runing then
    bmdthrdMain.Stop;
end;

procedure TfrmMainKombat.tmrMainTimer(Sender: TObject);
begin
  try
    statbarMain.Panels[0].Text := FormatDateTime('dd-mm-yyyy hh:nn:ss', Now);
  except

  end;
end;

procedure TfrmMainKombat.bmdthrdMainStart(Sender: TObject;
  Thread: TBMDExecuteThread; var Data: Pointer);
begin
  btnStartStop.Glyph := nil;
  imglstToolbar.GetBitmap(4, btnStartStop.Glyph);
end;

procedure TfrmMainKombat.bmdthrdMainTerminate(Sender: TObject;
  Thread: TBMDExecuteThread; var Data: Pointer);
begin
  btnStartStop.Glyph := nil;
  imglstToolbar.GetBitmap(3, btnStartStop.Glyph);
end;

procedure TfrmMainKombat.btnConnectDisconnectClick(Sender: TObject);
begin
  comportMainKombat.Connected := not comportMainKombat.Connected;
end;

procedure TfrmMainKombat.comportMainKombatAfterClose(Sender: TObject);
begin
  btnConnectDisconnect.Glyph := nil;
  imglstToolbar.GetBitmap(1, btnConnectDisconnect.Glyph);
  btnStartStop.Enabled := False;
  statbarMain.Panels[1].Text := 'Offline';
end;

procedure TfrmMainKombat.comportMainKombatAfterOpen(Sender: TObject);
begin
  btnConnectDisconnect.Glyph := nil;
  imglstToolbar.GetBitmap(0, btnConnectDisconnect.Glyph);
  btnStartStop.Enabled := True;
  statbarMain.Panels[1].Text := 'Online';
end;

procedure TfrmMainKombat.FormDestroy(Sender: TObject);
begin
  try
    if comportMainKombat.Connected then
      comportMainKombat.Close;
  except

  end;
end;

procedure TfrmMainKombat.btnClearChartClick(Sender: TObject);
begin
  {
    ShowMessage(
      IntToHex(modbus_crc(#1#5), 2)
      );
  }
  if MessageDlg(#13'Clear all chart?', mtConfirmation, [mbYes, mbNo],
    MB_ICONQUESTION) = mryes then
  begin
    //reset chart
    ChartReset(chtTekanan);
    ChartReset(chtSuhu);
    ChartReset(chtRH);
    ChartReset(chtWindSpeed);
  end;
end;

procedure TfrmMainKombat.btnTesChartClick(Sender: TObject);
var
  i: Integer;
  rr: Real;
  pr: ^Real;
  r1: string;
  pix: ^Integer;

  cc: Cardinal;
  pc: PCardinal;
  iyv: LongInt;
begin

  ChartReset(chtTekanan);
  for i := 1 to 30 do
  begin
    //    ChartPlotValue(chtTekanan, fstlnsrsTekanan,
    //      SampelDataPressureAltitude[i][2],
    //      SampelDataPressureAltitude[i][1],
    //      FloatToStr(SampelDataPressureAltitude[i][2]),
    //      clDefault);

    fstlnsrsTekanan.Add(SampelDataPressureAltitude[i][1], FormatFloat('#0.000',
      SampelDataPressureAltitude[i][2]), clDefault);
  end;

  //  iyv := fstlnsrsTekanan.YValues.Locate(10679);
  //  if (iyv <> -1) then
  //  begin
  //    fstlnsrsTekanan.XValue[iyv] := 100;
  //  end;
  //
  //  ShowMessage(IntToStr(iyv));

    //  r1 := #0#1#2#3#6#7;
    //  //  pr := @rr;
    //  pc := @cc;
    //  Move(r1[1], pc^, 4);
    //  asm
    //    ror cc,24
    //  end;
    //  lbl1.Caption := IntToStr(cc);

    //  ShowMessage(IntToHex(modbus_crc(#$00#$FF#$01#$00),4));

  AddLastFlightInfoData(lvLastInfo, 0, -2.04864984, 103.1314141, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0);
end;

procedure TfrmMainKombat.lvDataLogInsert(Sender: TObject; Item: TListItem);
begin
  try
    Item.MakeVisible(True);
  except
  end;
end;

procedure TfrmMainKombat.btnSetHomePositionClick(Sender: TObject);
begin
  with frmHomePosition do
  begin
    with payloadDataContent do
    begin
      frmHomePosition.rxcurrencyedtHomeLat.Value := GPSHomeLat;
      frmHomePosition.rxcurrencyedtHomeLongitude.Value := GPSHomeLon;
      frmHomePosition.rxcurrencyedtHomeAltitude.Value := GPSHomeAltitude;
    end;
  end;

  if frmHomePosition.ShowModal = mrok then
  begin
    with payloadDataContent do
    begin
      GPSHomeLat := frmHomePosition.rxcurrencyedtHomeLat.Value;
      GPSHomeLon := frmHomePosition.rxcurrencyedtHomeLongitude.Value;
      GPSHomeAltitude := frmHomePosition.rxcurrencyedtHomeAltitude.Value;
    end;

    //save ke cfg.ini
    with TIniFile.Create(Path + 'balon_cfg.ini') do
    begin
      WriteFloat('home', 'lat', payloadDataContent.GPSHomeLat);
      WriteFloat('home', 'lon', payloadDataContent.GPSHomeLon);
      WriteFloat('home', 'altitude', payloadDataContent.GPSHomeAltitude);
      Free;
    end;

    MessageDlg(#13'Home position sets', mtInformation, [mbOK],
      MB_ICONINFORMATION);
  end;
end;

procedure TfrmMainKombat.btnConfigSaveClick(Sender: TObject);
begin
  with TIniFile.Create(Path + 'balon_cfg.ini') do
  begin
    WriteInteger('time', 'poll interval', seConfigCmdPollTime.Value);
    WriteInteger('time', 'reply timeout', seConfigCmdTimeout.Value);
  end;

  payloadDataAcq.updateInterval := seConfigCmdPollTime.Value * 1000;

  MessageDlg(#13'Setting saved', mtInformation, [mbOK], MB_ICONINFORMATION);
end;

end.

