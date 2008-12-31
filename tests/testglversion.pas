{ -*- compile-command: "./compile_console.sh" -*- }
{
  Copyright 2008 Michalis Kamburelis.

  This file is part of test_kambi_units.

  test_kambi_units is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  test_kambi_units is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with test_kambi_units; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
}

unit TestGLVersion;

interface

uses fpcunit, testutils, testregistry;

type
  TTestGLVersion = class(TTestCase)
  published
    procedure Test1;
  end;

implementation

uses SysUtils, GLVersionUnit;

procedure TTestGLVersion.Test1;
var
  G: TGLVersion;
begin
  G := TGLVersion.Create('1.4 (2.1 Mesa 7.0.4)', 'Mesa project: www.mesa3d.org');
  try
    Assert(G.VendorVersion = '(2.1 Mesa 7.0.4)');
    Assert(G.Vendor = 'Mesa project: www.mesa3d.org');

    Assert(G.Major = 1);
    Assert(G.Minor = 4);

    { Test AtLeast method }
    Assert(G.AtLeast(0, 9));
    Assert(G.AtLeast(1, 0));
    Assert(G.AtLeast(1, 3));
    Assert(G.AtLeast(1, 4));
    Assert(not G.AtLeast(1, 5));
    Assert(not G.AtLeast(2, 0));

    Assert(not G.ReleaseExists);

    Assert(G.IsMesa);
    Assert(G.MesaMajor = 7);
    Assert(G.MesaMinor = 0);
    Assert(G.MesaRelease = 4);
  finally FreeAndNil(G) end;

  G := TGLVersion.Create('2.1 Mesa 7.1', 'Brian Paul');
  try
    Assert(G.VendorVersion = 'Mesa 7.1');
    Assert(G.Vendor = 'Brian Paul');

    Assert(G.Major = 2);
    Assert(G.Minor = 1);

    Assert(not G.ReleaseExists);

    Assert(G.IsMesa);
    Assert(G.MesaMajor = 7);
    Assert(G.MesaMinor = 1);
    Assert(G.MesaRelease = 0);
  finally FreeAndNil(G) end;

  G := TGLVersion.Create('1.2.3', 'foobar');
  try
    Assert(G.VendorVersion = '');
    Assert(G.Vendor = 'foobar');

    Assert(G.Major = 1);
    Assert(G.Minor = 2);
    Assert(G.ReleaseExists);
    Assert(G.Release = 3);
    Assert(not G.IsMesa);
  finally FreeAndNil(G) end;
end;

initialization
  RegisterTest(TTestGLVersion);
end.
