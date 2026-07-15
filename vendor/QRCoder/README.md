# QRCoder

- Version: 1.4.3
- Source: https://github.com/codebude/QRCoder/tree/v1.4.3
- License: MIT (`LICENSE.txt`)
- Included assembly: `lib/net40/QRCoder.dll` from the official NuGet package

The desktop PS1 uses this assembly to generate DG-Lab Socket binding QR codes locally. The desktop build embeds the assembly into `OCWritingFocus.exe` so the published application does not need an external QR service or a sidecar DLL.
