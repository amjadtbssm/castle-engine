program TestPaint;
uses SysUtils,
  CastleWindow, CastleImages, CastleGLImages, CastlePaint, castle_base,
  CastleVectors, CastleColors, CastleLog;

const
  TestSize = 100;
  HalfTestSize = TestSize div 2;
  NTests = 5;

var
  Window: TCastleWindow;
  RGBAlphaImageGL, RGBImageGL, GrayscaleAlphaImageGL, GrayscaleImageGL, RGBFloatImageGL: TGLImage;
  RGBAlphaImage, RGBImage, GrayscaleAlphaImage, GrayscaleImage, RGBFloatImage: TCastleImage;

procedure DoTest(aImage: TCastleImage);
begin
  aImage.Clear(Vector4Byte(255, 255, 255, 255));
  aImage.FillCircle(HalfTestSize + 0 * TestSize, HalfTestSize, TestSize/3, Lime);
  aImage.QuickFillCircle(HalfTestSize + 1 * TestSize, HalfTestSize, TestSize div 3, Lime);
  aImage.Circle(HalfTestSize + 2 * TestSize, HalfTestSize, TestSize div 3, 1, Lime);
  aImage.QuickCircle(HalfTestSize + 3 * TestSize, HalfTestSize, TestSize div 3, 1, Lime);
end;

procedure DoDraw;
begin
  RGBAlphaImage := TRGBAlphaImage.Create(TestSize*NTests, TestSize);
  DoTest(RGBAlphaImage);
  RGBAlphaImageGL := TGLImage.Create(RGBAlphaImage,true,true);
  {-------------}
  RGBImage := TRGBImage.Create(TestSize*NTests, TestSize);
  DoTest(RGBImage);
  RGBImageGL := TGLImage.Create(RGBImage,true,true);
  {-------------}
  GrayscaleAlphaImage := TGrayscaleAlphaImage.Create(TestSize*NTests, TestSize);
  DoTest(GrayscaleAlphaImage);
  GrayscaleAlphaImageGL := TGLImage.Create(GrayscaleAlphaImage,true,true);
  {-------------}
  GrayscaleImage := TGrayscaleImage.Create(TestSize*NTests, TestSize);
  DoTest(GrayscaleImage);
  GrayscaleImageGL := TGLImage.Create(GrayscaleImage,true,true);
  {-------------}
  RGBFloatImage := TRGBFloatImage.Create(TestSize*NTests, TestSize);
  DoTest(RGBFloatImage);
  RGBFloatImageGL := TGLImage.Create(RGBFloatImage,true,true);
end;

procedure DoRender(Container: TUIContainer);
begin
  RGBAlphaImageGL.Draw(0, 0 * TestSize);
  RGBImageGL.Draw(0, 1 * TestSize);
  GrayscaleAlphaImageGL.Draw(0, 2 * TestSize);
  GrayscaleImageGL.Draw(0, 3 * TestSize);
  RGBFloatImageGL.Draw(0, 4 * TestSize);
end;

begin
  InitializeLog;

  Window := TCastleWindow.Create(Application);
  Window.Width := NTests * TestSize;
  Window.Height := 5 * TestSize;
  Window.OnRender := @DoRender;

  DoDraw;

  Window.OpenAndRun;

  FreeAndNil(RGBAlphaImageGL);
  FreeAndNil(RGBImageGL);
  FreeAndNil(GrayscaleAlphaImageGL);
  FreeAndNil(GrayscaleImageGL);
  FreeAndNil(RGBFloatImageGL);
end.

