{
  Copyright 2018-2019 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Load 3D models in the glTF 2.0 format (@link(LoadGLTF)). }
unit X3DLoadInternalGLTF;

{$I castleconf.inc}

interface

uses X3DNodes, X3DFields;

{ Load 3D model in the GLTF format, converting it to an X3D nodes graph.
  This routine is internally used by the @link(Load3D) to load an GLTF file. }
function LoadGLTF(const URL: string): TX3DRootNode;

implementation

uses SysUtils, Classes, TypInfo, Math, PasGLTF,
  CastleClassUtils, CastleDownload, CastleUtils, CastleURIUtils, CastleLog,
  CastleVectors, CastleStringUtils, CastleTextureImages, CastleQuaternions,
  CastleImages, CastleVideos, CastleTimeUtils,
  X3DLoadInternalUtils;

{ Reading glTF using PasGLTF from Bero:
  https://github.com/BeRo1985/pasgltf/

  To understand glTF, and PasGLTF API, see the glTF specification:
  https://github.com/KhronosGroup/glTF/tree/master/specification/2.0
  This unit converts glTF to an X3D scene graph,
  so you should be familiar with X3D as well:
  https://castle-engine.io/vrml_x3d.php

  Some larger TODOs:

  - In the future, we would like to avoid using
    Accessor.DecodeAsXxx. Instead we should load binary data straight to GPU,
    looking at buffers, already exposed by PasGLTF.
    New X3D node, like BufferGeometry (same as X3DOM) will need to be
    invented for this, and CastleGeometryArrays will need to be rearranged.

  - We do not support PBR materials yet.

  - glTF skinned animations are not supported.
    (Animating transformations (translation, rotation, scale) is supported OK.)

  See https://castle-engine.io/planned_features.php .
}

type
  { X3D Appearance node extended to carry some additional information specified
    in glTF materials. }
  TGltfAppearanceNode = class(TAppearanceNode)
  public
    DoubleSided: Boolean;
  end;

function LoadGLTF(const URL: string): TX3DRootNode;
var
  BaseUrl: String;
  Document: TPasGLTF.TDocument;
  // List of TGltfAppearanceNode nodes, ordered just list glTF materials
  Appearances: TX3DNodeList;
  { List of TTransformNode nodes, ordered just list glTF nodes.
    Only initialized (non-nil and enough Count) for nodes that we created in ReadNode. }
  Nodes: TX3DNodeList;
  DefaultAppearance: TGltfAppearanceNode;

  procedure ReadHeader;
  begin
    WritelnLogMultiline('glTF', Format(
      'Asset.Copyright: %s' + NL +
      'Asset.Generator: %s' + NL +
      'Asset.MinVersion: %s' + NL +
      'Asset.Version: %s' + NL +
      'Asset.Empty: %s' + NL +
      'Accessors: %d' + NL +
      'Animations: %d' + NL +
      'Buffers: %d' + NL +
      'BufferViews: %d' + NL +
      'Cameras: %d' + NL +
      'Images: %d' + NL +
      'Materials: %d' + NL +
      'Meshes: %d' + NL +
      'Nodes: %d' + NL +
      'Samplers: %d' + NL +
      'Scenes: %d' + NL +
      'Skins: %d' + NL +
      'Textures: %d' + NL +
      'ExtensionsUsed: %s' + NL +
      'ExtensionsRequired: %s' + NL +
      '',
      [Document.Asset.Copyright,
       Document.Asset.Generator,
       Document.Asset.MinVersion,
       Document.Asset.Version,
       BoolToStr(Document.Asset.Empty, true),

       Document.Accessors.Count,
       Document.Animations.Count,
       Document.Buffers.Count,
       Document.BufferViews.Count,
       Document.Cameras.Count,
       Document.Images.Count,
       Document.Materials.Count,
       Document.Meshes.Count,
       Document.Nodes.Count,
       Document.Samplers.Count,
       Document.Scenes.Count,
       Document.Skins.Count,
       Document.Textures.Count,
       Document.ExtensionsUsed.Text,
       Document.ExtensionsRequired.Text
      ])
    );
    if Document.ExtensionsRequired.IndexOf('KHR_draco_mesh_compression') <> -1 then
      WritelnWarning('Required extension KHR_draco_mesh_compression not supported by glTF reader');
  end;

  function Vector3FromGltf(const V: TPasGLTF.TVector3): TVector3;
  begin
    // as it happens, both structures have the same memory layout, so copy by a fast Move
    Assert(SizeOf(V) = SizeOf(Result));
    Move(V, Result, SizeOf(Result));
  end;

  function Vector4FromGltf(const V: TPasGLTF.TVector4): TVector4;
  begin
    // as it happens, both structures have the same memory layout, so copy by a fast Move
    Assert(SizeOf(V) = SizeOf(Result));
    Move(V, Result, SizeOf(Result));
  end;

  function Matrix4FromGltf(const M: TPasGLTF.TMatrix4x4): TMatrix4;
  begin
    // as it happens, both structures have the same memory layout, so copy by a fast Move
    Assert(SizeOf(M) = SizeOf(Result));
    Move(M, Result, SizeOf(Result));
  end;

  { Convert glTF rotation (quaternion) to X3D (axis-angle). }
  function RotationFromGltf(const V: TPasGLTF.TVector4): TVector4;
  var
    RotationQuaternion: TQuaternion;
  begin
    RotationQuaternion.Data.Vector4 := Vector4FromGltf(V);
    Result := RotationQuaternion.ToAxisAngle;
  end;

  function ReadTextureRepeat(const Wrap: TPasGLTF.TSampler.TWrappingMode): Boolean;
  begin
    Result :=
      (Wrap = TPasGLTF.TSampler.TWrappingMode.Repeat_) or
      (Wrap = TPasGLTF.TSampler.TWrappingMode.MirroredRepeat);
    if Wrap = TPasGLTF.TSampler.TWrappingMode.MirroredRepeat then
      WritelnWarning('glTF', 'MirroredRepeat wrap mode not supported, using simple Repeat');
  end;

  function ReadMinificationFilter(const Filter: TPasGLTF.TSampler.TMinFilter): TAutoMinificationFilter;
  begin
    case Filter of
      TPasGLTF.TSampler.TMinFilter.None                : Result := minDefault;
      TPasGLTF.TSampler.TMinFilter.Nearest             : Result := minNearest;
      TPasGLTF.TSampler.TMinFilter.Linear              : Result := minLinear;
      TPasGLTF.TSampler.TMinFilter.NearestMipMapNearest: Result := minNearestMipmapNearest;
      TPasGLTF.TSampler.TMinFilter.LinearMipMapNearest : Result := minLinearMipmapNearest;
      TPasGLTF.TSampler.TMinFilter.NearestMipMapLinear : Result := minNearestMipmapLinear;
      TPasGLTF.TSampler.TMinFilter.LinearMipMapLinear  : Result := minLinearMipmapLinear;
      else raise EInternalError.Create('Unexpected glTF minification filter');
    end;
  end;

  function ReadMagnificationFilter(const Filter: TPasGLTF.TSampler.TMagFilter): TAutoMagnificationFilter;
  begin
    case Filter of
      TPasGLTF.TSampler.TMagFilter.None   : Result := magDefault;
      TPasGLTF.TSampler.TMagFilter.Nearest: Result := magNearest;
      TPasGLTF.TSampler.TMagFilter.Linear : Result := magLinear;
      else raise EInternalError.Create('Unexpected glTF magnification filter');
    end;
  end;

  procedure ReadTexture(const GltfTextureAtMaterial: TPasGLTF.TMaterial.TTexture;
    out Texture: TAbstractX3DTexture2DNode; out TexCoordinateId: Integer);
  var
    GltfTexture: TPasGLTF.TTexture;
    GltfImage: TPasGLTF.TImage;
    GltfSampler: TPasGLTF.TSampler;
    TextureProperties: TTexturePropertiesNode;
    Stream: TMemoryStream;
  begin
    Texture := nil;
    TexCoordinateId := GltfTextureAtMaterial.TexCoord;

    if not GltfTextureAtMaterial.Empty then
    begin
      if GltfTextureAtMaterial.Index < Document.Textures.Count then
      begin
        GltfTexture := Document.Textures[GltfTextureAtMaterial.Index];

        if Between(GltfTexture.Source, 0, Document.Images.Count - 1) then
        begin
          GltfImage := Document.Images[GltfTexture.Source];
          if GltfImage.URI <> '' then
          begin
            if FfmpegVideoMimeType(URIMimeType(GltfImage.URI), false) then
            begin
              Texture := TMovieTextureNode.Create('', BaseUrl);
              TMovieTextureNode(Texture).SetUrl([GltfImage.URI]);
              TMovieTextureNode(Texture).FlipVertically := true;
              TMovieTextureNode(Texture).Loop := true;
            end else
            begin
              Texture := TImageTextureNode.Create('', BaseUrl);
              TImageTextureNode(Texture).SetUrl([GltfImage.URI]);

              { glTF specification defines (0,0) texture coord to be
                at top-left corner, while X3D and OpenGL and OpenGLES expect it be
                at bottom-left corner.
                See
                https://castle-engine.io/x3d_implementation_texturing_extensions.php#section_flip_vertically
                for a detailed discussion.

                So we flip the textures.
                This way we can use original texture coordinates from glTF
                file (no need to process them, by doing "y := 1 - y"). }
              TImageTextureNode(Texture).FlipVertically := true;
            end;
          end else
          if GltfImage.BufferView >= 0 then
          begin
            { Use GltfImage.GetResourceData to load from buffer
              (instead of an external file). In particular, this is necessary to
              support GLB format with textures.

              Note that we use GltfImage.GetResourceData only when
              GltfImage.BufferView was set. Otherwise, we want to interpret URI
              by CGE code, thus allowing to read files using our Download()
              that understands also http/https, castle-data, castle-android-assets etc.
            }
            Stream := TMemoryStream.Create;
            try
              GltfImage.GetResourceData(Stream);
              Stream.Position := 0;

              { TODO: In case this is a DDS/KTX file, by using LoadImage
                we lose information about additional mipmaps,
                cubemap faces etc. }

              Texture := TPixelTextureNode.Create;
              try
                TPixelTextureNode(Texture).FdImage.Value :=
                  LoadImage(Stream, GltfImage.MimeType, []);
              except
                on E: Exception do
                  WritelnWarning('glTF', 'Cannot load the texture from glTF binary buffer with mime type %s: %s',
                    [GltfImage.MimeType, ExceptMessage(E)]);
              end;

              { Same reason as for TImageTextureNode.FlipVertically above:
                glTF specification defines (0,0) texture coord to be
                at top-left corner. }
              TPixelTextureNode(Texture).FdImage.Value.FlipVertical;
            finally FreeAndNil(Stream) end;
          end;
        end;

        if Between(GltfTexture.Sampler, 0, Document.Samplers.Count - 1) then
        begin
          GltfSampler := Document.Samplers[GltfTexture.Sampler];

          Texture.RepeatS := ReadTextureRepeat(GltfSampler.WrapS);
          Texture.RepeatT := ReadTextureRepeat(GltfSampler.WrapT);

          if (GltfSampler.MinFilter <> TPasGLTF.TSampler.TMinFilter.None) or
             (GltfSampler.MagFilter <> TPasGLTF.TSampler.TMagFilter.None) then
          begin
            TextureProperties := TTexturePropertiesNode.Create;
            TextureProperties.MinificationFilter := ReadMinificationFilter(GltfSampler.MinFilter);
            TextureProperties.MagnificationFilter := ReadMagnificationFilter(GltfSampler.MagFilter);
            Texture.TextureProperties := TextureProperties;
          end;
        end;
      end;
    end;
  end;

  function ReadAppearance(const Material: TPasGLTF.TMaterial): TGltfAppearanceNode;
  var
    CommonSurfaceShader: TCommonSurfaceShaderNode;
    BaseColorFactor: TVector4;
    BaseColorTexture, NormalTexture, EmissiveTexture: TAbstractX3DTexture2DNode;
    BaseColorTextureCoordinateId, NormalTextureCoordinateId, EmissiveTextureCoordinateId: Integer;
    AlphaChannel: TAutoAlphaChannel;
    //MetallicFactor, RoughnessFactor: TPasGLTFFloat;
    EmissiveFactor: TVector3;
  begin
    Result := TGltfAppearanceNode.Create(Material.Name);

    BaseColorFactor := Vector4FromGltf(Material.PBRMetallicRoughness.BaseColorFactor);
    EmissiveFactor := Vector3FromGltf(Material.EmissiveFactor);
    // MetallicFactor := Material.PBRMetallicRoughness.MetallicFactor;
    // RoughnessFactor := Material.PBRMetallicRoughness.RoughnessFactor;

    CommonSurfaceShader := TCommonSurfaceShaderNode.Create;
    CommonSurfaceShader.DiffuseFactor := BaseColorFactor.XYZ;
    CommonSurfaceShader.AlphaFactor := BaseColorFactor.W;
    // metallic/roughness conversion idea from X3DOM
    // CommonSurfaceShader.SpecularFactor := Vector3(
    //   Lerp(0.04, BaseColorFactor.X, MetallicFactor),
    //   Lerp(0.04, BaseColorFactor.Y, MetallicFactor),
    //   Lerp(0.04, BaseColorFactor.Z, MetallicFactor)
    // );
    // CommonSurfaceShader.ShininessFactor := 1 - RoughnessFactor;
    CommonSurfaceShader.EmissiveFactor := EmissiveFactor;
    Result.SetShaders([CommonSurfaceShader]);

    Result.DoubleSided := Material.DoubleSided;

    ReadTexture(Material.PBRMetallicRoughness.BaseColorTexture,
      BaseColorTexture, BaseColorTextureCoordinateId);
    CommonSurfaceShader.MultiDiffuseAlphaTexture := BaseColorTexture;
    CommonSurfaceShader.DiffuseTextureCoordinatesId := BaseColorTextureCoordinateId;

    ReadTexture(Material.NormalTexture,
      NormalTexture, NormalTextureCoordinateId);
    CommonSurfaceShader.NormalTexture := NormalTexture;
    CommonSurfaceShader.NormalTextureCoordinatesId := NormalTextureCoordinateId;

    ReadTexture(Material.EmissiveTexture,
      EmissiveTexture, EmissiveTextureCoordinateId);
    CommonSurfaceShader.EmissiveTexture := EmissiveTexture;
    CommonSurfaceShader.EmissiveTextureCoordinatesId := EmissiveTextureCoordinateId;

    // read alpha channel treatment
    case Material.AlphaMode of
      TPasGLTF.TMaterial.TAlphaMode.Opaque: AlphaChannel := acNone;
      TPasGLTF.TMaterial.TAlphaMode.Blend : AlphaChannel := acBlending;
      TPasGLTF.TMaterial.TAlphaMode.Mask  : AlphaChannel := acTest;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('Unexpected glTF Material.AlphaMode value');
      {$endif}
    end;
    Result.AlphaChannel := AlphaChannel;

    // TODO: ignored for now:
    // Result.AlphaClipThreshold := Material.AlphaCutOff;
    // Implement AlphaClipThreshold from X3DOM / InstantReality:
    // https://doc.x3dom.org/author/Shape/Appearance.html
    // https://www.x3dom.org/news/
    // (our default 0.5?)
  end;

  function AccessorTypeToStr(const AccessorType: TPasGLTF.TAccessor.TType): String;
  begin
    Result := GetEnumName(TypeInfo(TPasGLTF.TAccessor.TType), Ord(AccessorType));
  end;

  function PrimitiveModeToStr(const Mode: TPasGLTF.TMesh.TPrimitive.TMode): String;
  begin
    Result := GetEnumName(TypeInfo(TPasGLTF.TMesh.TPrimitive.TMode), Ord(Mode));
  end;

  function GetAccessor(const AccessorIndex: Integer): TPasGLTF.TAccessor;
  begin
    if AccessorIndex < Document.Accessors.Count then
      Result := Document.Accessors[AccessorIndex]
    else
    begin
      Result := nil;
      WritelnWarning('glTF', 'Missing glTF accessor (index %d, but we only have %d accessors)',
        [AccessorIndex, Document.Accessors.Count]);
    end;
  end;

  { The argument ForVertex addresses this statement of the glTF spec:
    """
    For performance and compatibility reasons, each element of
    a vertex attribute must be aligned to 4-byte boundaries
    inside bufferView
    """ }

  procedure AccessorToInt32(const AccessorIndex: Integer; const Field: TMFLong; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTFInt32DynamicArray;
    Len: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsInt32Array(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      if Len <> 0 then
        Move(A[0], Field.Items.List^[0], SizeOf(LongInt) * Len);
    end;
  end;

  procedure AccessorToFloat(const AccessorIndex: Integer; const Field: TMFFloat; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTFFloatDynamicArray;
    Len: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsFloatArray(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      if Len <> 0 then
        // Both glTF and X3D call it "Float", it is "Single" in Pascal
        Move(A[0], Field.Items.List^[0], SizeOf(Single) * Len);
    end;
  end;

  procedure AccessorToVector2(const AccessorIndex: Integer; const Field: TMFVec2f; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTF.TVector2DynamicArray;
    Len: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsVector2Array(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      if Len <> 0 then
        Move(A[0], Field.Items.List^[0], SizeOf(TVector2) * Len);
    end;
  end;

  procedure AccessorToVector3(const AccessorIndex: Integer; const Field: TMFVec3f; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTF.TVector3DynamicArray;
    Len: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsVector3Array(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      if Len <> 0 then
        Move(A[0], Field.Items.List^[0], SizeOf(TVector3) * Len);
    end;
  end;

  procedure AccessorToVector4(const AccessorIndex: Integer; const Field: TMFVec4f; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTF.TVector4DynamicArray;
    Len: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsVector4Array(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      if Len <> 0 then
        Move(A[0], Field.Items.List^[0], SizeOf(TVector4) * Len);
    end;
  end;

  procedure AccessorToRotation(const AccessorIndex: Integer; const Field: TMFRotation; const ForVertex: Boolean);
  var
    Accessor: TPasGLTF.TAccessor;
    A: TPasGLTF.TVector4DynamicArray;
    Len, I: Integer;
  begin
    Accessor := GetAccessor(AccessorIndex);
    if Accessor <> nil then
    begin
      A := Accessor.DecodeAsVector4Array(ForVertex);
      Len := Length(A);
      Field.Count := Len;
      // convert glTF rotation to X3D
      for I := 0 to Len - 1 do
        Field.Items.List^[I] := RotationFromGltf(A[I]);
    end;
  end;

  { Set SingleTexCoord as a texture coordinate.
    Sets up TexCoordField as a TMultiTextureCoordinateNode instance,
    in case we have multiple texture coordinates. }
  procedure SetMultiTextureCoordinate(const TexCoordField: TSFNode;
    const SingleTexCoord: TTextureCoordinateNode;
    const SingleTexCoordIndex: Integer);
  var
    MultiTexCoord: TMultiTextureCoordinateNode;
  begin
    if TexCoordField.Value <> nil then
      { only this procedure modifies this field,
        so it has to be TMultiTextureCoordinateNode if assigned. }
      MultiTexCoord := TexCoordField.Value as TMultiTextureCoordinateNode
    else
    begin
      MultiTexCoord := TMultiTextureCoordinateNode.Create;
      TexCoordField.Value := MultiTexCoord;
    end;

    MultiTexCoord.FdTexCoord.Count := Max(MultiTexCoord.FdTexCoord.Count, SingleTexCoordIndex + 1);
    MultiTexCoord.FdTexCoord.Items[SingleTexCoordIndex] := SingleTexCoord;
  end;

  procedure ReadPrimitive(const Primitive: TPasGLTF.TMesh.TPrimitive;
    const ParentGroup: TGroupNode);
  var
    AttributeName: TPasGLTFUTF8String;
    Shape: TShapeNode;
    Geometry: TAbstractGeometryNode;
    Coord: TCoordinateNode;
    TexCoord: TTextureCoordinateNode;
    Normal: TNormalNode;
    Color: TColorNode;
    ColorRGBA: TColorRGBANode;
    ColorAccessor: TPasGLTF.TAccessor;
    IndexField: TMFLong;
    TexCoordIndex: LongInt;
    Appearance: TGltfAppearanceNode;
  begin
    // create X3D geometry and shape nodes
    if Primitive.Indices <> -1 then
    begin
      case Primitive.Mode of
        TPasGLTF.TMesh.TPrimitive.TMode.Lines        : Geometry := TIndexedLineSetNode.CreateWithShape(Shape);
        // TODO: these will require unpacking and expressing as TIndexedLineSetNode
        //TPasGLTF.TMesh.TPrimitive.TMode.LineLoop     : Geometry := TIndexedLineSetNode.CreateWithShape(Shape);
        //TPasGLTF.TMesh.TPrimitive.TMode.LineStrip    : Geometry := TIndexedLineSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.Triangles    : Geometry := TIndexedTriangleSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.TriangleStrip: Geometry := TIndexedTriangleStripSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.TriangleFan  : Geometry := TIndexedTriangleFanSetNode.CreateWithShape(Shape);
        else
          begin
            WritelnWarning('glTF', 'Primitive mode not implemented (in indexed mode): ' + PrimitiveModeToStr(Primitive.Mode));
            Exit;
          end;
      end;
    end else
    begin
      case Primitive.Mode of
        TPasGLTF.TMesh.TPrimitive.TMode.Lines        : Geometry := TLineSetNode.CreateWithShape(Shape);
        // TODO: these will require unpacking and expressing as TIndexedLineSetNode
        //TPasGLTF.TMesh.TPrimitive.TMode.LineLoop     : Geometry := TIndexedLineSetNode.CreateWithShape(Shape);
        //TPasGLTF.TMesh.TPrimitive.TMode.LineStrip    : Geometry := TIndexedLineSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.Triangles    : Geometry := TTriangleSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.TriangleStrip: Geometry := TTriangleStripSetNode.CreateWithShape(Shape);
        TPasGLTF.TMesh.TPrimitive.TMode.TriangleFan  : Geometry := TTriangleFanSetNode.CreateWithShape(Shape);
        else
          begin
            WritelnWarning('glTF', 'Primitive mode not implemented (in non-indexed) mode: ' + PrimitiveModeToStr(Primitive.Mode));
            Exit;
          end;
      end;
    end;

    // read indexes
    IndexField := Geometry.CoordIndexField;
    if IndexField <> nil then
    begin
      Assert(Primitive.Indices <> -1);
      AccessorToInt32(Primitive.Indices, IndexField, false);
    end;

    // parse attributes (initializing Coord, TexCoord and other such nodes)
    // TODO: ForVertex true for all, or just for POSITION?
    for AttributeName in Primitive.Attributes.Keys do
    begin
      if (AttributeName = 'POSITION') and (Geometry.CoordField <> nil) then
      begin
        Coord := TCoordinateNode.Create;
        AccessorToVector3(Primitive.Attributes[AttributeName], Coord.FdPoint, true);
        Geometry.CoordField.Value := Coord;
      end else
      if IsPrefix('TEXCOORD_', AttributeName, false) and (Geometry.TexCoordField <> nil) then
      begin
        TexCoordIndex := StrToInt(PrefixRemove('TEXCOORD_', AttributeName, false));
        TexCoord := TTextureCoordinateNode.Create;
        AccessorToVector2(Primitive.Attributes[AttributeName], TexCoord.FdPoint, false);
        SetMultiTextureCoordinate(Geometry.TexCoordField, TexCoord, TexCoordIndex);
      end else
      if (AttributeName = 'NORMAL') and (Geometry is TAbstractComposedGeometryNode) then
      begin
        Normal := TNormalNode.Create;
        AccessorToVector3(Primitive.Attributes[AttributeName], Normal.FdVector, false);
        TAbstractComposedGeometryNode(Geometry).FdNormal.Value := Normal;
      end else
      if (AttributeName = 'COLOR_0') and (Geometry.ColorField <> nil) then
      begin
        ColorAccessor := GetAccessor(Primitive.Attributes[AttributeName]);
        if ColorAccessor.Type_ = TPasGLTF.TAccessor.TType.Vec4 then
        begin
          ColorRGBA := TColorRGBANode.Create;
          AccessorToVector4(Primitive.Attributes[AttributeName], ColorRGBA.FdColor, false);
          Geometry.ColorField.Value := ColorRGBA;
        end else
        begin
          Color := TColorNode.Create;
          AccessorToVector3(Primitive.Attributes[AttributeName], Color.FdColor, false);
          Geometry.ColorField.Value := Color;
        end;
      end else
      if (AttributeName = 'TANGENT') then
      begin
        { Don't do anything -- we don't store tangents now,
          but we can reliably calculate them when needed,
          so don't warn about them being unimplemented. }
      end else
        WritelnLog('glTF', 'Ignoring vertex attribute ' + AttributeName + ', not implemented (for this primitive mode)');
    end;

    // determine Apperance
    if Between(Primitive.Material, 0, Appearances.Count - 1) then
      Appearance := Appearances[Primitive.Material] as TGltfAppearanceNode
    else
    begin
      Appearance := DefaultAppearance;
      if Primitive.Material <> -1 then
        WritelnWarning('glTF', 'Primitive specifies invalid material index %d',
          [Primitive.Material]);
    end;
    Shape.Appearance := Appearance;

    // apply additional TGltfAppearanceNode parameters, specified in X3D at geometry
    Geometry.Solid := not Appearance.DoubleSided;

    // add to X3D
    ParentGroup.AddChildren(Shape);
  end;

  procedure ReadMesh(const Mesh: TPasGLTF.TMesh; const ParentGroup: TAbstractX3DGroupingNode);
  var
    Primitive: TPasGLTF.TMesh.TPrimitive;
    Group: TGroupNode;
  begin
    Group := TGroupNode.Create;
    Group.X3DName := Mesh.Name;
    ParentGroup.AddChildren(Group);

    for Primitive in Mesh.Primitives do
      ReadPrimitive(Primitive, Group);
  end;

  procedure ReadMesh(const MeshIndex: Integer; const ParentGroup: TAbstractX3DGroupingNode);
  begin
    if Between(MeshIndex, 0, Document.Meshes.Count - 1) then
      ReadMesh(Document.Meshes[MeshIndex], ParentGroup)
    else
      WritelnWarning('glTF', 'Mesh index invalid: %d', [MeshIndex]);
  end;

  procedure ReadCamera(const Camera: TPasGLTF.TCamera; const ParentGroup: TAbstractX3DGroupingNode);
  var
    OrthoViewpoint: TOrthoViewpointNode;
    Viewpoint: TViewpointNode;
  begin
    if Camera.Type_ = TPasGLTF.TCamera.TCameraType.Orthographic then
    begin
      OrthoViewpoint := TOrthoViewpointNode.Create;
      OrthoViewpoint.X3DName := Camera.Name;
      ParentGroup.AddChildren(OrthoViewpoint);
    end else
    begin
      Viewpoint := TViewpointNode.Create;
      Viewpoint.X3DName := Camera.Name;
      if Camera.Perspective.YFov <> 0 then
        Viewpoint.FieldOfView := Camera.Perspective.YFov / 2;
      ParentGroup.AddChildren(Viewpoint);
    end;
  end;

  procedure ReadCamera(const CameraIndex: Integer; const ParentGroup: TAbstractX3DGroupingNode);
  begin
    if Between(CameraIndex, 0, Document.Cameras.Count - 1) then
      ReadCamera(Document.Cameras[CameraIndex], ParentGroup)
    else
      WritelnWarning('glTF', 'Camera index invalid: %d', [CameraIndex]);
  end;

  procedure ReadNode(const NodeIndex: Integer; const ParentGroup: TAbstractX3DGroupingNode);
  var
    Node: TPasGLTF.TNode;
    Transform: TTransformNode;
    NodeMatrix: TMatrix4;
    Translation, Scale: TVector3;
    Rotation: TVector4;
    ChildNodeIndex: Integer;
  begin
    if Between(NodeIndex, 0, Document.Nodes.Count - 1) then
    begin
      Node := Document.Nodes[NodeIndex];
      NodeMatrix := Matrix4FromGltf(Node.Matrix);

      if not TMatrix4.PerfectlyEquals(NodeMatrix, TMatrix4.Identity) then
      begin
        MatrixDecompose(NodeMatrix, Translation, Rotation, Scale);
      end else
      begin
        Translation := Vector3FromGltf(Node.Translation);
        Rotation := RotationFromGltf(Node.Rotation);
        Scale := Vector3FromGltf(Node.Scale);
      end;

      Transform := TTransformNode.Create;
      Transform.X3DName := Node.Name;
      // needs name, to save to file animations with ROUTEs to this node
      if Transform.X3DName = '' then
        Transform.X3DName := 'Node' + IntToStr(NodeIndex);
      Transform.Translation := Translation;
      Transform.Rotation := Rotation;
      Transform.Scale := Scale;
      ParentGroup.AddChildren(Transform);

      if Node.Mesh <> -1 then
        ReadMesh(Node.Mesh, Transform);

      if Node.Camera <> -1 then
        ReadCamera(Node.Camera, Transform);

      for ChildNodeIndex in Node.Children do
        ReadNode(ChildNodeIndex, Transform);

      // add to Nodes list
      Nodes.Count := Max(Nodes.Count, NodeIndex + 1);
      if Nodes[NodeIndex] <> nil then
        WritelnWarning('glTF', 'Node %d read multiple times (impossible if glTF is a strict tree)', [NodeIndex])
      else
        Nodes[NodeIndex] := Transform;
    end else
      WritelnWarning('glTF', 'Node index invalid: %d', [NodeIndex]);
  end;

  procedure ReadScene(const SceneIndex: Integer; const ParentGroup: TAbstractX3DGroupingNode);
  var
    Scene: TPasGLTF.TScene;
    NodeIndex: Integer;
  begin
    if Between(SceneIndex, 0, Document.Scenes.Count - 1) then
    begin
      Scene := Document.Scenes[SceneIndex];
      for NodeIndex in Scene.Nodes do
        ReadNode(NodeIndex, ParentGroup);
    end else
      WritelnWarning('glTF', 'Scene index invalid: %d', [SceneIndex]);
  end;

type
  // Which TTransformNode field is animated
  TGltfSamplerPath = (
    gsTranslation,
    gsRotation,
    gsScale
  );

  function ReadSampler(const Sampler: TPasGLTF.TAnimation.TSampler;
    const Node: TTransformNode;
    const Path: TGltfSamplerPath;
    const TimeSensor: TTimeSensorNode;
    const ParentGroup: TAbstractX3DGroupingNode;
    out Duration: TFloatTime): TAbstractInterpolatorNode;
  var
    InterpolateVector3: TPositionInterpolatorNode;
    InterpolateRotation: TOrientationInterpolatorNode;
    Interpolator: TAbstractInterpolatorNode;
    Route: TX3DRoute;
    InterpolatorOutputEvent: TX3DEvent;
    TargetField: TX3DField;
    I: Integer;
  begin
    case Path of
      gsTranslation, gsScale:
        begin
          InterpolateVector3 := TPositionInterpolatorNode.Create;
          Interpolator := InterpolateVector3;
          InterpolatorOutputEvent := InterpolateVector3.EventValue_changed;
          AccessorToVector3(Sampler.Output, InterpolateVector3.FdKeyValue, false);
          case Path of
            gsTranslation: TargetField := Node.FdTranslation;
            gsScale      : TargetField := Node.FdScale;
            else raise EInternalError.Create('ReadSampler vector3 - Path?');
          end;
        end;
      gsRotation:
        begin
          InterpolateRotation := TOrientationInterpolatorNode.Create;
          Interpolator := InterpolateRotation;
          InterpolatorOutputEvent := InterpolateRotation.EventValue_changed;
          AccessorToRotation(Sampler.Output, InterpolateRotation.FdKeyValue, false);
          TargetField := Node.FdRotation;
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('ReadSampler - Path?');
      {$endif}
    end;

    Interpolator.X3DName := 'Animate_' + TargetField.X3DName + '_' + TimeSensor.X3DName;

    AccessorToFloat(Sampler.Input, Interpolator.FdKey, false);
    if Interpolator.FdKey.Count <> 0 then
      Duration := Interpolator.FdKey.Items.Last
    else
      Duration := 0;

    ParentGroup.AddChildren(Interpolator);

    Route := TX3DRoute.Create;
    Route.SetSourceDirectly(TimeSensor.EventFraction_changed);
    Route.SetDestinationDirectly(Interpolator.EventSet_fraction);
    ParentGroup.AddRoute(Route);

    Route := TX3DRoute.Create;
    Route.SetSourceDirectly(InterpolatorOutputEvent);
    Route.SetDestinationDirectly(TargetField);
    ParentGroup.AddRoute(Route);

    Result := Interpolator;

    // take into account Interpolation
    case Sampler.Interpolation of
      TPasGLTF.TAnimation.TSampler.TSamplerType.Linear: ; // nothing to do
      TPasGLTF.TAnimation.TSampler.TSamplerType.Step:
        begin
          WritelnWarning('Animation interpolation Step not supported now, will be Linear');
        end;
      TPasGLTF.TAnimation.TSampler.TSamplerType.CubicSpline:
        begin
          WritelnWarning('Animation interpolation "CubicSpline" not supported yet, approximating by "Linear"');
          case Path of
            gsTranslation, gsScale:
              begin
                if InterpolateVector3.FdKeyValue.Count <>
                   InterpolateVector3.FdKey.Count * 3 then
                begin
                  WritelnWarning('For "CubicSpline", expected 3 output values for each input time, got %d for %d', [
                    InterpolateVector3.FdKeyValue.Count,
                    InterpolateVector3.FdKey.Count
                  ]);
                  Exit;
                end;
                for I := 0 to InterpolateVector3.FdKeyValue.Count div 3 - 1 do
                  InterpolateVector3.FdKeyValue.Items[I] :=
                    InterpolateVector3.FdKeyValue.Items[3 * I + 1];
                InterpolateVector3.FdKeyValue.Count := InterpolateVector3.FdKeyValue.Count div 3;
              end;
            gsRotation:
              begin
                if InterpolateRotation.FdKeyValue.Count <>
                   InterpolateRotation.FdKey.Count * 3 then
                begin
                  WritelnWarning('For "CubicSpline", expected 3 output values for each input time, got %d for %d', [
                    InterpolateRotation.FdKeyValue.Count,
                    InterpolateRotation.FdKey.Count
                  ]);
                  Exit;
                end;
                for I := 0 to InterpolateRotation.FdKeyValue.Count div 3 - 1 do
                  InterpolateRotation.FdKeyValue.Items[I] :=
                    InterpolateRotation.FdKeyValue.Items[3 * I + 1];
                InterpolateRotation.FdKeyValue.Count := InterpolateRotation.FdKeyValue.Count div 3;
              end;
            {$ifndef COMPILER_CASE_ANALYSIS}
            else raise EInternalError.Create('ReadSampler - Path?');
            {$endif}
          end;
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else
        begin
          WritelnWarning('Given animation interpolation is not supported');
        end;
      {$endif}
    end;

    // TODO: reset fields not used by this animation, but possibly changed by others?
  end;

  procedure ReadAnimation(const Animation: TPasGLTF.TAnimation; const ParentGroup: TAbstractX3DGroupingNode);
  var
    TimeSensor: TTimeSensorNode;
    Channel: TPasGLTF.TAnimation.TChannel;
    Sampler: TPasGLTF.TAnimation.TSampler;
    Node: TTransformNode;
    Duration, MaxDuration: TFloatTime;
    Interpolators: TX3DNodeList;
    Interpolator: TAbstractInterpolatorNode;
    NodeIndex, I: Integer;
  begin
    TimeSensor := TTimeSensorNode.Create;
    if Animation.Name = '' then
      { Needs a name, otherwise
        1. TCastleSceneCore.AnimationsList ignores this,
        2. saving ROUTEs using it to a file would be impossible }
      TimeSensor.X3DName := 'unnamed'
    else
      TimeSensor.X3DName := Animation.Name;
    ParentGroup.AddChildren(TimeSensor);

    MaxDuration := 0;
    Interpolators := TX3DNodeList.Create(false);
    try
      for Channel in Animation.Channels do
      begin
        NodeIndex := Channel.Target.Node;

        // glTF spec says "When node isn't defined, channel should be ignored"
        if NodeIndex = -1 then
          Continue;

        if not (Between(NodeIndex, 0, Nodes.Count - 1) and (Nodes[NodeIndex] <> nil)) then
        begin
          WritelnWarning('Node index %d indicated by animation %s was not imported', [
            NodeIndex,
            TimeSensor.X3DName
          ]);
          Continue;
        end;

        Node := Nodes[NodeIndex] as TTransformNode;

        // read Sampler
        if not Between(Channel.Sampler, 0, Animation.Samplers.Count - 1) then
        begin
          WritelnWarning('Invalid animation "%s" sampler index %d', [
            TimeSensor.X3DName,
            Channel.Sampler
          ]);
          Continue;
        end;

        Sampler := Animation.Samplers[Channel.Sampler];

        // read channel Path, call ReadSampler with all information
        case Channel.Target.Path of
          'translation':
            Interpolator := ReadSampler(Sampler, Node, gsTranslation, TimeSensor, ParentGroup, Duration);
          'rotation':
            Interpolator := ReadSampler(Sampler, Node, gsRotation, TimeSensor, ParentGroup, Duration);
          'scale':
            Interpolator := ReadSampler(Sampler, Node, gsScale, TimeSensor, ParentGroup, Duration);
          else
            begin
              WritelnWarning('Animating "%s" not supported', [Channel.Target.Path]);
              Continue;
            end;
        end;

        Interpolators.Add(Interpolator);
        MaxDuration := Max(MaxDuration, Duration);
      end;

      // adjust TimeSensor duration, scale the keys in all Interpolators to be in 0..1 range
      if MaxDuration <> 0 then
      begin
        TimeSensor.CycleInterval := MaxDuration;
        for I := 0 to Interpolators.Count - 1 do
        begin
          Interpolator := Interpolators[I] as TAbstractInterpolatorNode;
          Interpolator.FdKey.Items.MultiplyAll(1 / MaxDuration);
        end;
      end;
    finally FreeAndNil(Interpolators) end;
  end;

var
  Stream: TStream;
  Material: TPasGLTF.TMaterial;
  Animation: TPasGLTF.TAnimation;
begin
  { Make absolute URL.

    This also makes the later Document.RootPath calculation correct.
    Otherwise "InclPathDelim(ExtractFilePath(URIToFilenameSafe('my_file.gtlf')))"
    would result in '/' (accidentally making all TPasGLTF.TImage.URI values
    relative to root directory on Unix). This was reproducible doing
    "view3dscene my_file.gtlf" on the command-line. }
  BaseUrl := AbsoluteURI(URL);

  Stream := Download(URL, []);
  try
    Result := TX3DRootNode.Create('', BaseUrl);
    try
      Document := nil;
      DefaultAppearance := nil;
      Appearances := nil;
      Nodes := nil;
      try
        Document := TPasGLTF.TDocument.Create;
        Document.RootPath := InclPathDelim(ExtractFilePath(URIToFilenameSafe(BaseUrl)));
        Document.LoadFromStream(Stream);

        ReadHeader;

        // read appearances (called "materials" in glTF; in X3D "material" is something smaller)
        DefaultAppearance := TGltfAppearanceNode.Create;
        DefaultAppearance.Material := TMaterialNode.Create;
        DefaultAppearance.DoubleSided := false;
        Appearances := TX3DNodeList.Create(false);
        for Material in Document.Materials do
          Appearances.Add(ReadAppearance(Material));

        // read main scene
        Nodes := TX3DNodeList.Create(false);
        if Document.Scene <> -1 then
          ReadScene(Document.Scene, Result)
        else
        begin
          WritelnWarning('glTF does not specify a default scene to render. We will import the 1st scene, if available.');
          ReadScene(0, Result);
        end;

        // read animations
        for Animation in Document.Animations do
          ReadAnimation(Animation, Result);
      finally
        FreeIfUnusedAndNil(DefaultAppearance);
        X3DNodeList_FreeUnusedAndNil(Appearances);
        X3DNodeList_FreeUnusedAndNil(Nodes);
        FreeAndNil(Document);
      end;
    except FreeAndNil(Result); raise end;
  finally FreeAndNil(Stream) end;
end;

end.
