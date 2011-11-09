# An ActionScript library for all things Lytro

Right now, it reads .lft files and you can display the various bitmaps within in Flash Player.

In the future, it'll hopefully be able to do more than Lytro's own viewer.

Based off of the two existing, open-source .lfp parsers that were around when this AS3 version began:
 * https://github.com/DamonOehlman/lytroview
 * https://github.com/nrpatel/lfptools

## Usage

### Synchronous Decoding

```actionscript
var pic:LightFieldPicture = LFPDecoder.decode(bytes)
var s:LightFieldSprite = new LightFieldSprite(pic)
addChild(s)
```

### Asynchronous Decoding

```actionscript
LFPDecoder.decodeAsync(bytes, onLFPComplete)

function onLFPComplete(picture:LightFieldPicture):void {
	var s:LightFieldSprite = new LightFieldSprite(picture)
	addChild(s)
}
```