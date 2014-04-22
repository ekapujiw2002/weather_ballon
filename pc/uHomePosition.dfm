object frmHomePosition: TfrmHomePosition
  Left = 515
  Top = 229
  BorderIcons = [biSystemMenu]
  BorderStyle = bsSingle
  Caption = 'Home Position'
  ClientHeight = 115
  ClientWidth = 211
  Color = clBtnFace
  Font.Charset = ANSI_CHARSET
  Font.Color = clBlack
  Font.Height = -13
  Font.Name = 'Consolas'
  Font.Style = []
  OldCreateOrder = False
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object lbl1: TLabel
    Left = 8
    Top = 12
    Width = 56
    Height = 15
    Caption = 'Latitude'
  end
  object lbl2: TLabel
    Left = 8
    Top = 36
    Width = 63
    Height = 15
    Caption = 'Longitude'
  end
  object lbl3: TLabel
    Left = 8
    Top = 60
    Width = 56
    Height = 15
    Caption = 'Altitude'
  end
  object rxcurrencyedtHomeLat: TCurrencyEdit
    Left = 80
    Top = 8
    Width = 121
    Height = 23
    DecimalPlaceRound = True
    DecimalPlaces = 7
    DisplayFormat = ',0.0000000;-,0.0000000'
    MaxValue = 90.000000000000000000
    MinValue = -90.000000000000000000
    TabOrder = 0
  end
  object rxcurrencyedtHomeLongitude: TCurrencyEdit
    Left = 80
    Top = 32
    Width = 121
    Height = 23
    DecimalPlaceRound = True
    DecimalPlaces = 7
    DisplayFormat = ',0.0000000;-,0.0000000'
    MaxValue = 180.000000000000000000
    MinValue = -180.000000000000000000
    TabOrder = 1
  end
  object rxcurrencyedtHomeAltitude: TCurrencyEdit
    Left = 80
    Top = 56
    Width = 121
    Height = 23
    DecimalPlaceRound = True
    DisplayFormat = ',0.00;-,0.00'
    MaxValue = 10000.000000000000000000
    TabOrder = 2
  end
  object btnHomeSet: TBitBtn
    Left = 80
    Top = 83
    Width = 41
    Height = 25
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 3
  end
end
