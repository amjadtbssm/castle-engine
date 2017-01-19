{ -*- buffer-read-only: t -*-

  Copyright 2015-2017 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatically generated X3D node class helpers.
  Do not edit manually, instead regenerate using
  castle_game_engine/src/x3d/doc/generate_x3d_nodes_to_pascal.lpr . }

{$ifdef read_interface}

  private
    function GetSrcFactor: string;
    procedure SetSrcFactor(const Value: string);
    function GetDestFactor: string;
    procedure SetDestFactor(const Value: string);
    function GetColor: TCastleColorRGB;
    procedure SetColor(const Value: TCastleColorRGB);
    function GetColorTransparency: Single;
    procedure SetColorTransparency(const Value: Single);
  public
    property SrcFactor: string read GetSrcFactor write SetSrcFactor;
    property DestFactor: string read GetDestFactor write SetDestFactor;
    property Color: TCastleColorRGB read GetColor write SetColor;
    property ColorTransparency: Single read GetColorTransparency write SetColorTransparency;

{$endif read_interface}

{$ifdef read_implementation}

{ TBlendModeNode ----------------------------------------------- }

function TBlendModeNode.GetSrcFactor: string;
begin
  Result := FdSrcFactor.Value;
end;

procedure TBlendModeNode.SetSrcFactor(const Value: string);
begin
  FdSrcFactor.Send(Value);
end;

function TBlendModeNode.GetDestFactor: string;
begin
  Result := FdDestFactor.Value;
end;

procedure TBlendModeNode.SetDestFactor(const Value: string);
begin
  FdDestFactor.Send(Value);
end;

function TBlendModeNode.GetColor: TCastleColorRGB;
begin
  Result := FdColor.Value;
end;

procedure TBlendModeNode.SetColor(const Value: TCastleColorRGB);
begin
  FdColor.Send(Value);
end;

function TBlendModeNode.GetColorTransparency: Single;
begin
  Result := FdColorTransparency.Value;
end;

procedure TBlendModeNode.SetColorTransparency(const Value: Single);
begin
  FdColorTransparency.Send(Value);
end;

{$endif read_implementation}