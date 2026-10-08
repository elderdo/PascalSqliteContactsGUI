unit UtilsTests;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Types, Utils;

type

  { TSplitNameTests }

  TSplitNameTests = class(TTestCase)
  published
    procedure EmptyStringGivesTwoEmptyNames;
    procedure SingleWordGivesFirstOnly;
    procedure TwoWordsGiveFirstAndLast;
    procedure ExtraWordsAreDropped;
  end;

  { TValidatePhoneTests }

  TValidatePhoneTests = class(TTestCase)
  published
    procedure TenDigitsIsAccepted;
    procedure LowestAndHighestTenDigitNumbersAreAccepted;
    procedure NineDigitsIsRejected;
    procedure ElevenDigitsIsRejected;
    procedure NonNumericIsRejected;
    procedure EmptyStringIsRejected;
    procedure FormattedNumberIsRejected;
  end;

implementation

{ TSplitNameTests }

procedure TSplitNameTests.EmptyStringGivesTwoEmptyNames;
var
  Names: TStringDynArray;
begin
  Names := SplitName('');
  AssertEquals('count', 2, Length(Names));
  AssertEquals('first', '', Names[0]);
  AssertEquals('last', '', Names[1]);
end;

procedure TSplitNameTests.SingleWordGivesFirstOnly;
var
  Names: TStringDynArray;
begin
  Names := SplitName('Madonna');
  AssertEquals('count', 2, Length(Names));
  AssertEquals('first', 'Madonna', Names[0]);
  AssertEquals('last', '', Names[1]);
end;

procedure TSplitNameTests.TwoWordsGiveFirstAndLast;
var
  Names: TStringDynArray;
begin
  Names := SplitName('Ada Lovelace');
  AssertEquals('count', 2, Length(Names));
  AssertEquals('first', 'Ada', Names[0]);
  AssertEquals('last', 'Lovelace', Names[1]);
end;

procedure TSplitNameTests.ExtraWordsAreDropped;
var
  Names: TStringDynArray;
begin
  Names := SplitName('John Quincy Adams');
  AssertEquals('count', 2, Length(Names));
  AssertEquals('first', 'John', Names[0]);
  AssertEquals('last', 'Quincy', Names[1]);
end;

{ TValidatePhoneTests }

procedure TValidatePhoneTests.TenDigitsIsAccepted;
begin
  AssertEquals(9168490226, ValidatePhone('9168490226'));
end;

procedure TValidatePhoneTests.LowestAndHighestTenDigitNumbersAreAccepted;
begin
  AssertEquals(1000000000, ValidatePhone('1000000000'));
  AssertEquals(9999999999, ValidatePhone('9999999999'));
end;

procedure TValidatePhoneTests.NineDigitsIsRejected;
begin
  AssertEquals(-1, ValidatePhone('999999999'));
end;

procedure TValidatePhoneTests.ElevenDigitsIsRejected;
begin
  AssertEquals(-1, ValidatePhone('10000000000'));
end;

procedure TValidatePhoneTests.NonNumericIsRejected;
begin
  AssertEquals(-1, ValidatePhone('abcdefghij'));
end;

procedure TValidatePhoneTests.EmptyStringIsRejected;
begin
  AssertEquals(-1, ValidatePhone(''));
end;

procedure TValidatePhoneTests.FormattedNumberIsRejected;
begin
  AssertEquals(-1, ValidatePhone('916-849-0226'));
end;

initialization
  RegisterTest(TSplitNameTests);
  RegisterTest(TValidatePhoneTests);

end.
