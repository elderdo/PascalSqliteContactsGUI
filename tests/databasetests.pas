unit DatabaseTests;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, SQLDB, SQLite3Conn, Utils;

type

  { TDatabaseTestCase: each test gets a fresh, empty database built from the
    real schema file, in a temporary file that is deleted afterwards. }

  TDatabaseTestCase = class(TTestCase)
  private
    FDBFile: String;
    FConn: TSQLite3Connection;
    FTrans: TSQLTransaction;
  protected
    FQuery: TSQLQuery;
    procedure SetUp; override;
    procedure TearDown; override;
    function ScalarInt(const SQL: String): Integer;
    function ScalarStr(const SQL: String): String;
  end;

  { TPeopleTests }

  TPeopleTests = class(TDatabaseTestCase)
  published
    procedure AddUserReturnsNewId;
    procedure AddUserStoresNames;
    procedure AddUserHandlesApostrophe;
    procedure EditUserChangesNames;
    procedure DeleteUserRemovesRow;
  end;

  { TPhoneTests }

  TPhoneTests = class(TDatabaseTestCase)
  published
    procedure SchemaSeedsPhoneTypes;
    procedure AddPhoneReturnsNewId;
    procedure QueryPhonesReturnsOnlySelectedPerson;
    procedure EditPhoneChangesNumberAndType;
    procedure DeletePhoneRemovesRow;
    procedure DeleteUserDeletesTheirPhones;
  end;

implementation

{ TDatabaseTestCase }

procedure TDatabaseTestCase.SetUp;
var
  Schema: TStringList;
  SchemaFile: String;
  i: Integer;
begin
  FDBFile := IncludeTrailingPathDelimiter(GetTempDir(False)) +
             'hellocontacts_test_' + IntToStr(GetProcessID) + '.db';
  if FileExists(FDBFile) then
    DeleteFile(FDBFile);

  FConn := TSQLite3Connection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FQuery := TSQLQuery.Create(nil);

  FConn.DatabaseName := FDBFile;
  FConn.Transaction := FTrans;
  EnableForeignKeys(FConn);
  FTrans.Database := FConn;
  FQuery.Database := FConn;
  FQuery.Transaction := FTrans;
  FConn.Connected := True;

  SchemaFile := ExtractFilePath(ParamStr(0)) + '..' + PathDelim +
                'resources' + PathDelim + 'helloContacts-SCHEMA.sql';
  Schema := TStringList.Create;
  try
    Schema.LoadFromFile(SchemaFile);
    for i := 0 to Schema.Count - 1 do
      if Trim(Schema[i]) <> '' then
      begin
        FQuery.SQL.Text := Schema[i];
        FQuery.ExecSQL;
        FTrans.Commit;
      end;
  finally
    Schema.Free;
  end;
end;

procedure TDatabaseTestCase.TearDown;
begin
  FQuery.Free;
  FTrans.Free;
  FConn.Free;
  if FileExists(FDBFile) then
    DeleteFile(FDBFile);
end;

function TDatabaseTestCase.ScalarInt(const SQL: String): Integer;
begin
  FQuery.Close;
  FQuery.SQL.Text := SQL;
  FQuery.Open;
  Result := FQuery.Fields[0].AsInteger;
  FQuery.Close;
end;

function TDatabaseTestCase.ScalarStr(const SQL: String): String;
begin
  FQuery.Close;
  FQuery.SQL.Text := SQL;
  FQuery.Open;
  Result := FQuery.Fields[0].AsString;
  FQuery.Close;
end;

{ TPeopleTests }

procedure TPeopleTests.AddUserReturnsNewId;
var
  Id1, Id2: Integer;
begin
  Id1 := AddUser(FQuery, 'Ada', 'Lovelace');
  Id2 := AddUser(FQuery, 'Alan', 'Turing');
  AssertTrue('first id is valid', Id1 > 0);
  AssertTrue('second id is different', Id2 > Id1);
end;

procedure TPeopleTests.AddUserStoresNames;
var
  Id: Integer;
begin
  Id := AddUser(FQuery, 'Ada', 'Lovelace');
  AssertEquals('Ada', ScalarStr('SELECT First FROM People WHERE Id = ' + IntToStr(Id)));
  AssertEquals('Lovelace', ScalarStr('SELECT Last FROM People WHERE Id = ' + IntToStr(Id)));
end;

procedure TPeopleTests.AddUserHandlesApostrophe;
var
  Id: Integer;
begin
  Id := AddUser(FQuery, 'Conan', 'O''Brien');
  AssertTrue('insert succeeded', Id > 0);
  AssertEquals('O''Brien', ScalarStr('SELECT Last FROM People WHERE Id = ' + IntToStr(Id)));
end;

procedure TPeopleTests.EditUserChangesNames;
var
  Id: Integer;
begin
  Id := AddUser(FQuery, 'Ada', 'Lovelace');
  EditUser(FQuery, Id, 'Augusta', 'King');
  AssertEquals('Augusta', ScalarStr('SELECT First FROM People WHERE Id = ' + IntToStr(Id)));
  AssertEquals('King', ScalarStr('SELECT Last FROM People WHERE Id = ' + IntToStr(Id)));
  AssertEquals(1, ScalarInt('SELECT COUNT(*) FROM People'));
end;

procedure TPeopleTests.DeleteUserRemovesRow;
var
  Id: Integer;
begin
  Id := AddUser(FQuery, 'Ada', 'Lovelace');
  AddUser(FQuery, 'Alan', 'Turing');
  DeleteUser(FQuery, Id);
  AssertEquals(1, ScalarInt('SELECT COUNT(*) FROM People'));
  AssertEquals(0, ScalarInt('SELECT COUNT(*) FROM People WHERE Id = ' + IntToStr(Id)));
end;

{ TPhoneTests }

procedure TPhoneTests.SchemaSeedsPhoneTypes;
begin
  AssertEquals(3, ScalarInt('SELECT COUNT(*) FROM PhoneTypes'));
  AssertEquals('Cell', ScalarStr('SELECT Type FROM PhoneTypes WHERE Id = 1'));
end;

procedure TPhoneTests.AddPhoneReturnsNewId;
var
  PersonId, PhoneId: Integer;
begin
  PersonId := AddUser(FQuery, 'Ada', 'Lovelace');
  PhoneId := AddPhone(FQuery, PersonId, '9168490226', 1);
  AssertTrue('phone id is valid', PhoneId > 0);
  AssertEquals(1, ScalarInt('SELECT COUNT(*) FROM PhoneNumbers WHERE PersonId = ' + IntToStr(PersonId)));
end;

procedure TPhoneTests.QueryPhonesReturnsOnlySelectedPerson;
var
  Ada, Alan: Integer;
begin
  Ada := AddUser(FQuery, 'Ada', 'Lovelace');
  Alan := AddUser(FQuery, 'Alan', 'Turing');
  AddPhone(FQuery, Ada, '9165550001', 1);
  AddPhone(FQuery, Ada, '9165550002', 2);
  AddPhone(FQuery, Alan, '9165550003', 3);

  QueryPhones(FQuery, Ada);
  AssertEquals('Ada phone count', 2, FQuery.RecordCount);
  FQuery.Close;

  QueryPhones(FQuery, Alan);
  AssertEquals('Alan phone count', 1, FQuery.RecordCount);
  AssertEquals('Home', FQuery.FieldByName('Type').AsString);
  FQuery.Close;
end;

procedure TPhoneTests.EditPhoneChangesNumberAndType;
var
  PersonId, PhoneId: Integer;
begin
  PersonId := AddUser(FQuery, 'Ada', 'Lovelace');
  PhoneId := AddPhone(FQuery, PersonId, '9165550001', 1);
  EditPhone(FQuery, PhoneId, PersonId, '9165559999', 2);
  AssertEquals('9165559999', ScalarStr('SELECT Number FROM PhoneNumbers WHERE Id = ' + IntToStr(PhoneId)));
  AssertEquals(2, ScalarInt('SELECT PhoneTypeId FROM PhoneNumbers WHERE Id = ' + IntToStr(PhoneId)));
end;

procedure TPhoneTests.DeletePhoneRemovesRow;
var
  PersonId, PhoneId: Integer;
begin
  PersonId := AddUser(FQuery, 'Ada', 'Lovelace');
  PhoneId := AddPhone(FQuery, PersonId, '9165550001', 1);
  DeletePhone(FQuery, PhoneId);
  AssertEquals(0, ScalarInt('SELECT COUNT(*) FROM PhoneNumbers'));
end;

procedure TPhoneTests.DeleteUserDeletesTheirPhones;
var
  PersonId: Integer;
begin
  PersonId := AddUser(FQuery, 'Ada', 'Lovelace');
  AddPhone(FQuery, PersonId, '9165550001', 1);
  AddPhone(FQuery, PersonId, '9165550002', 2);
  DeleteUser(FQuery, PersonId);
  AssertEquals('phones left behind', 0, ScalarInt('SELECT COUNT(*) FROM PhoneNumbers'));
end;

initialization
  RegisterTest(TPeopleTests);
  RegisterTest(TPhoneTests);

end.
