{
  Copyright 2007-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Material and texture properties from external files (TMaterialProperty,
  global MaterialProperties collection). }
unit CastleMaterialProperties;

{$I castleconf.inc}

interface

uses Classes, DOM, Generics.Collections,
  CastleUtils, CastleClassUtils, CastleSoundEngine, CastleStringUtils,
  CastleImages, CastleFindFiles, CastleInternalAutoGenerated;

type
  { Information for a particular material. }
  TMaterialProperty = class
  strict private
    FTextureBaseName: string;
    FFootstepsSound: TSoundType;
    FToxic: boolean;
    FToxicDamageConst, FToxicDamageRandom, FToxicDamageTime: Single;
    FNormalMap: string;
    FAlphaChannel: string;
  private
    procedure LoadFromDOMElement(Element: TDOMElement; const BaseURL: string);
  public
    { Texture basename to associate this property will all appearances
      using given texture. For now, this is the only way to associate
      property, but more are possible in the future (like MaterialNodeName). }
    property TextureBaseName: string read FTextureBaseName write FTextureBaseName;

    { Footsteps sound to make when player is walking on this material.
      stNone is no information is available. }
    property FootstepsSound: TSoundType read FFootstepsSound write FFootstepsSound;

    { Is the floor toxic when walking on it.
      Taken into account only if you assign @link(TCastleSceneManager.Player).
      @groupBegin }
    property Toxic: boolean read FToxic write FToxic;
    property ToxicDamageConst: Single read FToxicDamageConst write FToxicDamageConst;
    property ToxicDamageRandom: Single read FToxicDamageRandom write FToxicDamageRandom;
    property ToxicDamageTime: Single read FToxicDamageTime write FToxicDamageTime;
    { @groupEnd }

    { Normal map texture URL. This is a simple method to activate bump mapping,
      equivalent to using normalMap field in an Appearance node of VRML/X3D, see
      https://castle-engine.io/x3d_extensions.php#section_ext_bump_mapping .

      In case both VRML/X3D Appearance specifies normalMap and we have
      NormalMap defined here, the VRML/X3D Appearance is used. }
    property NormalMap: string read FNormalMap write FNormalMap;

    { Override alpha channel type for diffuse texture.
      The meaning and allowed values for this are the same as for
      alphaChannel field for texture nodes, see
      https://castle-engine.io/x3d_extensions.php#section_ext_alpha_channel_detection .
      Empty value (default) doesn't change the alpha channel type
      (set in VRML/X3D or auto-detected). }
    property AlphaChannel: string read FAlphaChannel write FAlphaChannel;
  end;

  TTextureCompressionsToGenerate = record
    Compressions: TTextureCompressions;
    { In addition to Compressions,
      generate also the most suitable variant of DXTn compression. }
    DxtAutoDetect: boolean;
  end;

  { Store information that is naturally associated with a given material
    or texture in an external file. Documentation and example of such
    file is on  https://castle-engine.io/creating_data_material_properties.php .
    Right now this allows to define things like:

    @unorderedList(
      @itemSpacing compact
      @item footsteps,
      @item toxic ground (hurts player),
      @item bump mapping (normal maps and height maps for given texture),
      @item texture GPU-compressed and downscaled alternatives.
    )

    In the future, it should be possible to express all these properties
    in pure VRML/X3D (inside Appearance / Material / ImageTexture nodes).
    Right now, you can do this with bump mapping, see
    https://castle-engine.io/x3d_extensions.php#section_ext_bump_mapping ,
    but not footsteps or toxic ground.
    In the future it should also be possible to express these properties
    in 3D authoring software (like Blender), and easily export them
    to appropriate VRML/X3D nodes.
    For now, this TMaterialProperty allows us to easily customize materials
    in a way that is not possible in Blender.

    Using an external file for material properties has also long-term
    advantages: it can be shared across many 3D models, for example
    you can define footsteps sound for all grounds using the @code(grass.png)
    textures, in all levels, at once.

    You have to load an XML file by setting
    @link(TMaterialProperties.URL MaterialProperties.URL) property.
  }
  TMaterialProperties = class
  strict private
    type
      TAutoGeneratedTextures = class
      strict private
        const
          PathsIgnoreCase = true;
        var
        FAutoProcessImageURLs: boolean;
        IncludePaths: TCastleStringList; // absolute URLs
        IncludePathsRecursive: TBooleanList;
        ExcludePaths: TCastleStringList;
        { necessary for Exclude with relative dirs, like "entites/*", to work }
        FBaseURL: string;
        FCompressedFormatsToGenerate: TTextureCompressionsToGenerate;
        GatheringResult: TCastleStringList;
        FSmallestScale: Cardinal;
        FPreferredOutputFormat: String;
        FTrivialUncompressedConvert: Boolean;
        procedure GatherCallback(const FileInfo: TFileInfo; var StopSearch: boolean);
        procedure LoadImageEvent(var URL: string);
        function IsAbsoluteURLMatchingRelativeMask(const URL, Mask: string): boolean;
      public
        constructor Create(const Element: TDOMElement; const BaseURL: string; const AnAutoProcessImageURLs: boolean);
        destructor Destroy; override;
        function TextureURLMatches(const URL: string): boolean;
        function AutoGeneratedTextures: TCastleStringList;
        function GeneratedTextureURL(const URL: string;
          const UseCompression: boolean; const TextureCompression: TTextureCompression;
          const Scaling: Cardinal): string;
        property CompressedFormatsToGenerate: TTextureCompressionsToGenerate
          read FCompressedFormatsToGenerate;
        function CompressedFormatsGenerated: TTextureCompressions;
        property SmallestScale: Cardinal read FSmallestScale;
        property PreferredOutputFormat: String read FPreferredOutputFormat;
        property TrivialUncompressedConvert: Boolean read FTrivialUncompressedConvert;
      end;

      TAutoGeneratedTexturesList = {$ifdef CASTLE_OBJFPC}specialize{$endif} TObjectList<TAutoGeneratedTextures>;
      TMaterialPropertyList = {$ifdef CASTLE_OBJFPC}specialize{$endif} TObjectList<TMaterialProperty>;
    var
      FAutoGeneratedTexturesList: TAutoGeneratedTexturesList;
      FMaterialPropertyList: TMaterialPropertyList;
      FURL: string;
      FAutoProcessImageURLs: boolean;
    procedure SetURL(const Value: string);
    function AutoGeneratedTexturesInfo(const TextureURL: string): TAutoGeneratedTextures;
  public
    constructor Create(const AnAutoProcessImageURLs: boolean);
    destructor Destroy; override;

    { Load material properties from given XML file.
      Set this to empty string to unload previously loaded properties.
      See Castle1 and fps_game data for examples how this looks like,
      in @code(material_properties.xml). }
    property URL: string read FURL write SetURL;

    property FileName: string read FURL write SetURL; deprecated 'use URL';

    { Find material properties for given texture basename.
      Returns @nil if no material properties are found
      (in particular, if @link(URL) was not set yet). }
    function FindTextureBaseName(const TextureBaseName: string): TMaterialProperty;

    { Get the URLs of all textures that should have automatically
      generated GPU-compressed and downscaled counterparts.
      Returns a list of absolute URLs.
      This actually searches on disk, right now, to find the texture list,
      applying the include/exclude rules specified in material_properties.xml file.

      This is to be used by "castle-engine auto-generate-textures"
      tool, or similar tools.

      Caller is responsible for freeing the returned TCastleStringList list. }
    function AutoGeneratedTextures: TCastleStringList;

    { For given texture (absolute) URL and compression and scaling,
      return the proper (absolute) URL of auto-compressed and auto-downscaled counterpart.
      Scaling is defined just like TextureLoadingScale. }
    function AutoGeneratedTextureURL(const TextureURL: string;
      const UseCompression: boolean;
      const TextureCompression: TTextureCompression; const Scaling: Cardinal): string;

    { Automatic compression formats generated for this texture.
      @param(TextureURL An absolute texture URL. Usually should just be taken
        from AutoGeneratedTextures returned list.) }
    function AutoCompressedTextureFormats(const TextureURL: string):
      TTextureCompressionsToGenerate;

    { Automatically generated smallest scale, for this texture.
      Return value should be intepreted just like TextureLoadingScale.
      See https://castle-engine.io/creating_data_material_properties.php#section_texture_scale
      @param(TextureURL An absolute texture URL. Usually should just be taken
        from AutoGeneratedTextures returned list.) }
    function AutoScale(const TextureURL: string): Cardinal;

    { Perform trivial conversion (that does not compress, does not downscale)
      for this texture.
      @param(TextureURL An absolute texture URL. Usually should just be taken
        from AutoGeneratedTextures returned list.) }
    function TrivialUncompressedConvert(const TextureURL: string): Boolean;
  end;

{ Material and texture properties, see @link(TMaterialProperties).
  Set the @link(TMaterialProperties.URL URL) property
  to load material properties from XML file. }
function MaterialProperties: TMaterialProperties;

var
  { Use the auto-generated alternative downscaled images.
    This allows to conserve both GPU memory and loading time
    by using a downscaled images versions.

    The subset of your images which are affected by this must be declared inside
    the material_properties.xml file, which is loaded to @link(MaterialProperties).
    And the image files must be prepared earlier by the build tool call
    @code("castle-engine auto-generate-textures").
    See the https://castle-engine.io/creating_data_material_properties.php#section_texture_scale .

    Each size (width, height, and (for 3D images) depth) is scaled
    by 1 / 2^TextureLoadingScale.
    So value = 1 means no scaling, value = 2 means that each size is 1/2
    (texture area is 1/4), value = 3 means that each size is 1/4 and so on.

    This mechanism will @italic(not)
    automatically downscale textures at runtime. If the downscaled texture version
    should exist, according to the material_properties.xml file,
    but it doesn't, then texture loading will simply fail.
    If you want to scale the texture at runtime, use the similar @link(GLTextureScale)
    instead.

    This mechanism is independent from GLTextureScale:

    @unorderedList(
      @item(Scaling indicated by GLTextureScale is performed at runtime,
        after loading. It happens @bold(after) the results of
        TextureLoadingScale have already been applied.)

      @item(The GLTextureScale works on a different subset of textures.

        For GLTextureScale, the usage of a texture determines if it's a GUI texture
        (which cannot be scaled) or not.
        So textures loaded through TDrawableImage, or declared as guiTexture in X3D,
        are not affected by GLTextureScale. All other textures are affected.
        It doesn't matter from where they are loaded -- so it affects also
        texture contents created by code, or downloaded from the Internet.

        In contrast, the TextureLoadingScale works (only) on all the images
        declared as having a downscaled version in material_properties.xml.
        It is not affected by how the texture will be used.)

      @item(The GLTextureScale works only on texture formats that can be scaled.
        In particular, it cannot scale textures compressed with a GPU compression
        (S3TC and such). It silently ignores them.

        In contrast, the TextureLoadingScale can cooperate with GPU-compressed textures,
        if you also compress them automatically using the material_properties.xml
        and the build tool call @code("castle-engine auto-generate-textures").
        The downscaled image versions are generated from original (uncompressed,
        unscaled) images, and are then compressed.)

      @item(The GLTextureScale scaling is usually of worse quality, since it's
        done at runtime.

        In contrast, the downscaled textures used by TextureLoadingScale
        are generated as a preprocessing step.
        The build tool @code("castle-engine auto-generate-textures") may use
        a slower but higher-quality scaling.)
    )
  }
  TextureLoadingScale: Cardinal = 1;

implementation

uses SysUtils, XMLRead, StrUtils, Math,
  CastleXMLUtils, CastleFilesUtils, X3DNodes,
  CastleURIUtils, CastleDownload, CastleLog;

{ TMaterialProperty --------------------------------------------------------- }

procedure TMaterialProperty.LoadFromDOMElement(Element: TDOMElement; const BaseURL: string);
var
  FootstepsSoundName: string;
  ToxicDamage: TDOMElement;
  I: TXMLElementIterator;
begin
  if not Element.AttributeString('texture_base_name', FTextureBaseName) then
    raise Exception.Create('<properties> element must have "texture_base_name" attribute');

  FootstepsSoundName := '';
  if Element.AttributeString('footsteps_sound', FootstepsSoundName) and
     (FootstepsSoundName <> '') then
    FFootstepsSound := SoundEngine.SoundFromName(FootstepsSoundName) else
    FFootstepsSound := stNone;

  if Element.AttributeString('normal_map', FNormalMap) and (FNormalMap <> '') then
    FNormalMap := CombineURI(BaseURL, FNormalMap) else
    FNormalMap := '';

  if not Element.AttributeString('alpha_channel', FAlphaChannel) then
    FAlphaChannel := '';

  I := Element.ChildrenIterator;
  try
    while I.GetNext do
      if I.Current.TagName = 'toxic' then
      begin
        FToxic := true;
        ToxicDamage := I.Current.ChildElement('damage');
        if not ToxicDamage.AttributeSingle('const', FToxicDamageConst) then
          FToxicDamageConst := 0;
        if not ToxicDamage.AttributeSingle('random', FToxicDamageRandom) then
          FToxicDamageRandom := 0;
        if not ToxicDamage.AttributeSingle('time', FToxicDamageTime) then
          FToxicDamageTime := 0;
      end else
        raise Exception.CreateFmt('Unknown element inside <property>: "%s"',
          [I.Current.TagName]);
  finally FreeAndNil(I) end;
end;

{ TMaterialProperties.TAutoGeneratedTextures -------------------------------- }

constructor TMaterialProperties.TAutoGeneratedTextures.Create(
  const Element: TDOMElement; const BaseURL: string;
  const AnAutoProcessImageURLs: boolean);
var
  ChildElements: TXMLElementIterator;
  ChildElement, CompressElement, ScaleElement, PreferredOutputFormatElement: TDOMElement;
  TextureCompressionName: string;
begin
  inherited Create;
  FAutoProcessImageURLs := AnAutoProcessImageURLs;
  IncludePaths := TCastleStringList.Create;
  IncludePathsRecursive := TBooleanList.Create;
  ExcludePaths := TCastleStringList.Create;
  FBaseURL := BaseURL;

  { read from XML }

  ChildElements := Element.ChildrenIterator('include');
  try
    while ChildElements.GetNext do
    begin
      ChildElement := ChildElements.Current;
      IncludePaths.Add(ChildElement.AttributeURL('path', BaseURL));
      IncludePathsRecursive.Add(ChildElement.AttributeBooleanDef('recursive', false));
    end;
  finally FreeAndNil(ChildElements) end;

  ChildElements := Element.ChildrenIterator('exclude');
  try
    while ChildElements.GetNext do
    begin
      ChildElement := ChildElements.Current;
      ExcludePaths.Add(ChildElement.AttributeString('path'));
    end;
  finally FreeAndNil(ChildElements) end;

  // calculate FCompressedFormatsToGenerate
  CompressElement := Element.ChildElement('compress', false);
  if CompressElement <> nil then
  begin
    ChildElements := CompressElement.ChildrenIterator('format');
    try
      while ChildElements.GetNext do
      begin
        TextureCompressionName := ChildElements.Current.AttributeString('name');
        if LowerCase(TextureCompressionName) = 'dxt_autodetect' then
          FCompressedFormatsToGenerate.DxtAutoDetect := true
        else
          Include(FCompressedFormatsToGenerate.Compressions, StringToTextureCompression(TextureCompressionName));
      end;
    finally FreeAndNil(ChildElements) end;
  end;

  FSmallestScale := 1;
  ScaleElement := Element.ChildElement('scale', false);
  if ScaleElement <> nil then
  begin
    FSmallestScale := ScaleElement.AttributeCardinalDef('smallest', 1);
    if FSmallestScale < 1 then
      raise Exception.CreateFmt('Invalid scale smallest value "%d"', [FSmallestScale]);
  end;

  PreferredOutputFormatElement := Element.ChildElement('preferred_output_format', false);
  if PreferredOutputFormatElement <> nil then
    FPreferredOutputFormat := PreferredOutputFormatElement.AttributeStringDef('extension', '')
  else
    FPreferredOutputFormat := '.png';

  FTrivialUncompressedConvert := Element.ChildElement('trivial_uncompressed_convert', false) <> nil;

  if FAutoProcessImageURLs then
    AddLoadImageListener({$ifdef CASTLE_OBJFPC}@{$endif} LoadImageEvent);
end;

function TMaterialProperties.TAutoGeneratedTextures.CompressedFormatsGenerated: TTextureCompressions;
begin
  { TODO: for now, the DxtAutoDetect texture will not be used at all.
    The actual value of CompressedFormatsGenerated
    should come from auto_generated.xml. }
  Result := FCompressedFormatsToGenerate.Compressions;
end;

destructor TMaterialProperties.TAutoGeneratedTextures.Destroy;
begin
  FreeAndNil(IncludePaths);
  FreeAndNil(IncludePathsRecursive);
  FreeAndNil(ExcludePaths);
  if FAutoProcessImageURLs then
    RemoveLoadImageListener({$ifdef CASTLE_OBJFPC}@{$endif} LoadImageEvent);
  inherited;
end;

procedure TMaterialProperties.TAutoGeneratedTextures.GatherCallback(const FileInfo: TFileInfo; var StopSearch: boolean);
begin
  if (Pos('/' + TAutoGenerated.AutoGeneratedDirName + '/', FileInfo.URL) = 0) and
     IsImageMimeType(URIMimeType(FileInfo.URL), false, false) then
    GatheringResult.Add(FileInfo.URL);
end;

function TMaterialProperties.TAutoGeneratedTextures.IsAbsoluteURLMatchingRelativeMask(
  const URL, Mask: string): boolean;
var
  U: string;
begin
  U := PrefixRemove(ExtractURIPath(FBaseURL), URL, PathsIgnoreCase);
  Result := IsWild(U, Mask, PathsIgnoreCase);
end;

function TMaterialProperties.TAutoGeneratedTextures.
  AutoGeneratedTextures: TCastleStringList;

  procedure Exclude(const ExcludePathMask: string; const URLs: TCastleStringList);
  var
    I: Integer;
  begin
    I := 0;
    while I < URLs.Count do
    begin
      // Writeln('Excluding ExcludePathMask ' + ExcludePathMask +
      //   ' from ' + PrefixRemove(ExtractURIPath(FBaseURL), URLs[I], PathsIgnoreCase));
      if IsAbsoluteURLMatchingRelativeMask(URLs[I], ExcludePathMask) then
        URLs.Delete(I) else
        Inc(I);
    end;
  end;

var
  I: Integer;
  FindOptions: TFindFilesOptions;
begin
  Result := TCastleStringList.Create;
  GatheringResult := Result;

  for I := 0 to IncludePaths.Count - 1 do
  begin
    if IncludePathsRecursive[I] then
      FindOptions := [ffRecursive] else
      { not recursive, so that e.g. <include path="my_texture.png" />
	or <include path="subdir/my_texture.png" />
	should not include *all* my_texture.png files inside. }
      FindOptions := [];
    FindFiles(IncludePaths[I], false, {$ifdef CASTLE_OBJFPC}@{$endif} GatherCallback, FindOptions);
  end;

  GatheringResult := nil;

  for I := 0 to ExcludePaths.Count - 1 do
    Exclude(ExcludePaths[I], Result);
end;

function TMaterialProperties.TAutoGeneratedTextures.TextureURLMatches(const URL: string): boolean;

  { Check is URL not excluded. }
  function CheckNotExcluded: boolean;
  var
    I: Integer;
  begin
    for I := 0 to ExcludePaths.Count - 1 do
      if IsAbsoluteURLMatchingRelativeMask(URL, ExcludePaths[I]) then
        Exit(false);
    Result := true;
  end;

var
  URLName, URLPath: string;
  I: Integer;
  IncludePath, IncludeMask: string;
  PathMatches: boolean;
begin
  Result := false;
  URLPath := ExtractURIPath(URL);
  URLName := ExtractURIName(URL);
  for I := 0 to IncludePaths.Count - 1 do
  begin
    IncludePath := ExtractURIPath(IncludePaths[I]);
    IncludeMask := ExtractURIName(IncludePaths[I]);
    if IncludePathsRecursive[I] then
      PathMatches := IsPrefix(IncludePath, URLPath, PathsIgnoreCase) else
      PathMatches := AnsiSameText(IncludePath, URLPath); { assume PathsIgnoreCase=true }
    if PathMatches and IsWild(URLName, IncludeMask, PathsIgnoreCase) then
    begin
      Result := CheckNotExcluded;
      Exit;
    end;
  end;
end;

procedure TMaterialProperties.TAutoGeneratedTextures.LoadImageEvent(
  var URL: string);

  { Texture has GPU-compressed and/or downscaled counterpart, according to include/exclude
    variables. So try to replace URL with something compressed and downscaled. }
  procedure ReplaceURL;
  var
    C: TTextureCompression;
    Scale: Cardinal;
  begin
    { Do not warn about it, just as we don't warn when TextureLoadingScale = 2
      but we're loading image not mentioned in <auto_generated_textures>.
    if TextureLoadingScale > SmallestScale then
      raise Exception.CreateFmt('Invalid TextureLoadingScale %d, we do not have such downscaled images. You should add or modify the <scale smallest=".." /> declaration in "material_properties.xml", and make sure thar you load the "material_properties.xml" early enough.',
        [TextureLoadingScale]); }
    Scale := Min(SmallestScale, TextureLoadingScale);

    if not SupportedTextureCompressionKnown then
      WritelnWarning('MaterialProperties', 'Cannot determine whether to use auto-generated (GPU compressed and/or downscaled) texture version for ' + URL + ' because the image is loaded before GPU capabilities are known')
    else
    begin
      {$ifdef IOS}
      // Do not spam log about this, there's no easy solution for this now
      //WritelnWarning('MaterialProperties', 'TODO: Not using GPU compressed (and potentially downscaled) version for ' + URL + ' because on iOS non-square compressed textures are not supported');
      {$else}
      for C in CompressedFormatsGenerated do
        if C in SupportedTextureCompression then
        begin
          URL := GeneratedTextureURL(URL, true, C, Scale);
          WritelnLog('MaterialProperties', 'Using GPU compressed (and potentially downscaled) alternative ' + URL);
          Exit;
        end;
      {$endif}
    end;

    { no GPU compression supported; still, maybe we should use a downscaled alternative }
    if (Scale <> 1) or TrivialUncompressedConvert then
    begin
      URL := GeneratedTextureURL(URL, false, Low(TTextureCompression), Scale);
      WritelnLog('MaterialProperties', 'Using alternative ' + URL);
    end;
  end;

begin
  if TextureURLMatches(URL) then
    ReplaceURL;
end;

function TMaterialProperties.TAutoGeneratedTextures.GeneratedTextureURL(
  const URL: string;
  const UseCompression: boolean; const TextureCompression: TTextureCompression;
  const Scaling: Cardinal): string;
begin
  Result := ExtractURIPath(URL) + TAutoGenerated.AutoGeneratedDirName + '/';
  if UseCompression then
    Result := Result + LowerCase(TextureCompressionToString(TextureCompression)) + '/'
  else
    Result := Result + 'uncompressed/';
  if Scaling <> 1 then
    Result := Result + 'downscaled_' + IntToStr(Scaling) + '/';
  Result := Result + ExtractURIName(URL);
  if UseCompression then
    Result := Result + TextureCompressionInfo[TextureCompression].FileExtension
  else
    Result := Result + PreferredOutputFormat;
end;

{ TMaterialProperties ---------------------------------------------------------- }

constructor TMaterialProperties.Create(const AnAutoProcessImageURLs: boolean);
begin
  inherited Create;
  FAutoProcessImageURLs := AnAutoProcessImageURLs;
  FMaterialPropertyList := TMaterialPropertyList.Create({ owns objects } true);
  FAutoGeneratedTexturesList := TAutoGeneratedTexturesList.Create({ owns objects } true);
end;

destructor TMaterialProperties.Destroy;
begin
  FreeAndNil(FAutoGeneratedTexturesList);
  FreeAndNil(FMaterialPropertyList);
  inherited;
end;

procedure TMaterialProperties.SetURL(const Value: string);
var
  Config: TXMLDocument;
  Elements: TXMLElementIterator;
  MaterialProperty: TMaterialProperty;
  Stream: TStream;
begin
  FURL := Value;

  FMaterialPropertyList.Clear;
  FAutoGeneratedTexturesList.Clear;

  if URL = '' then Exit;

  Stream := Download(URL);
  try
    ReadXMLFile(Config, Stream, URL);
  finally FreeAndNil(Stream) end;

  try
    Check(Config.DocumentElement.TagName = 'properties',
      'Root node of material properties file must be <properties>');

    Elements := Config.DocumentElement.ChildrenIterator('property');
    try
      while Elements.GetNext do
      begin
        MaterialProperty := TMaterialProperty.Create;
        FMaterialPropertyList.Add(MaterialProperty);
        MaterialProperty.LoadFromDOMElement(Elements.Current, AbsoluteURI(URL));
      end;
    finally FreeAndNil(Elements); end;

    Elements := Config.DocumentElement.ChildrenIterator('auto_generated_textures');
    try
      while Elements.GetNext do
      begin
        FAutoGeneratedTexturesList.Add(
          TAutoGeneratedTextures.Create(Elements.Current, URL, FAutoProcessImageURLs));
      end;
    finally FreeAndNil(Elements); end;
  finally
    SysUtils.FreeAndNil(Config);
  end;
end;

function TMaterialProperties.FindTextureBaseName(const TextureBaseName: string): TMaterialProperty;
var
  I: Integer;
begin
  for I := 0 to FMaterialPropertyList.Count - 1 do
    if SameText(FMaterialPropertyList[I].TextureBaseName, TextureBaseName) then
      Exit(FMaterialPropertyList[I]);
  Result := nil;
end;

function TMaterialProperties.AutoGeneratedTextures: TCastleStringList;
var
  S: TCastleStringList;
  I, J: Integer;
begin
  Result := TCastleStringList.Create;
  try
    for I := 0 to FAutoGeneratedTexturesList.Count - 1 do
    begin
      S := FAutoGeneratedTexturesList[I].AutoGeneratedTextures;
      try
        for J := 0 to S.Count - 1 do
        begin
          if Result.IndexOf(S[J]) <> -1 then
            WritelnWarning('MaterialProperties', Format('The texture URL "%s" is under the influence of more than one <auto_generated_textures> rule. Use <include> and <exclude> to avoid it',
              [S[J]]))
          else
            Result.Add(S[J]);
        end;
      finally FreeAndNil(S) end;
    end;
  except FreeAndNil(Result); raise end;
end;

function TMaterialProperties.AutoGeneratedTexturesInfo(const TextureURL: string): TAutoGeneratedTextures;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FAutoGeneratedTexturesList.Count - 1 do
    if FAutoGeneratedTexturesList[I].TextureURLMatches(TextureURL) then
      Exit(FAutoGeneratedTexturesList[I]);
end;

function TMaterialProperties.AutoGeneratedTextureURL(const TextureURL: string;
  const UseCompression: boolean;
  const TextureCompression: TTextureCompression; const Scaling: Cardinal): string;
var
  Info: TAutoGeneratedTextures;
begin
  Info := AutoGeneratedTexturesInfo(TextureURL);
  if Info = nil then
    raise Exception.CreateFmt('Texture "%s" does not match any auto_generated_textures block',
      [TextureURL]);
  Result := Info.GeneratedTextureURL(TextureURL, UseCompression, TextureCompression, Scaling);
end;

function TMaterialProperties.AutoCompressedTextureFormats(const TextureURL: string):
  TTextureCompressionsToGenerate;
var
  Info: TAutoGeneratedTextures;
begin
  Info := AutoGeneratedTexturesInfo(TextureURL);
  if Info <> nil then
    Result := Info.CompressedFormatsToGenerate
  else
    // empty Result
    FillChar(Result, SizeOf(Result), 0);
end;

function TMaterialProperties.AutoScale(const TextureURL: string): Cardinal;
var
  Info: TAutoGeneratedTextures;
begin
  Info := AutoGeneratedTexturesInfo(TextureURL);
  if Info <> nil then
    Result := Info.SmallestScale
  else
    Result := 1;
end;

function TMaterialProperties.TrivialUncompressedConvert(const TextureURL: string): Boolean;
var
  Info: TAutoGeneratedTextures;
begin
  Info := AutoGeneratedTexturesInfo(TextureURL);
  if Info <> nil then
    Result := Info.TrivialUncompressedConvert
  else
    Result := false;
end;

{ globals -------------------------------------------------------------------- }

var
  FMaterialProperties: TMaterialProperties;

function MaterialProperties: TMaterialProperties;
begin
  if FMaterialProperties = nil then
    FMaterialProperties := TMaterialProperties.Create(true);
  Result := FMaterialProperties;
end;

finalization
  FreeAndNil(FMaterialProperties);
end.
