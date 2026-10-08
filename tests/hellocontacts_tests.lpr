program hellocontacts_tests;

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, consoletestrunner,
  UtilsTests, DatabaseTests;

type
  TTestApp = class(TTestRunner)
  end;

var
  App: TTestApp;

begin
  App := TTestApp.Create(nil);
  App.Initialize;
  App.Title := 'Hello Contacts unit tests';
  App.Run;
  App.Free;
end.
