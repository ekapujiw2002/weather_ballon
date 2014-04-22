unit uHomePosition;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Mask, rxToolEdit, rxCurrEdit, Buttons;

type
  TfrmHomePosition = class(TForm)
    lbl1: TLabel;
    rxcurrencyedtHomeLat: TCurrencyEdit;
    lbl2: TLabel;
    rxcurrencyedtHomeLongitude: TCurrencyEdit;
    lbl3: TLabel;
    rxcurrencyedtHomeAltitude: TCurrencyEdit;
    btnHomeSet: TBitBtn;
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmHomePosition: TfrmHomePosition;

implementation

{$R *.dfm}

end.
