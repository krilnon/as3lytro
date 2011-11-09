package lytro {
	import org.bytearray.decoder.JPEGDecoder
	
	import flash.events.*
	import flash.utils.*
	import flash.display.*
	
	/**
	 * Reads .lfp files and generates an abstraction for them (LightFieldPicture) suitable for use in Flash Player.
	 * 
	 * Based off of the two existing, open-source .lfp parsers that were around when this AS3 version began:
	 *		https://github.com/DamonOehlman/lytroview
	 * 		https://github.com/nrpatel/lfptools
	 * 
	 * @author	Krilnon
	 */
	public class LFPDecoder extends EventDispatcher {
		private static var
			_magic:Vector.<uint> = new <uint>[0x89, 0x4c, 0x46, 0x50, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x01]
		
		private var
			_bytes:ByteArray,
			_synchronous:Boolean,
			_picture:LightFieldPicture,
			_imageCount:uint
		
		/**
		 * A factory that simplifies the construction of this class.  Synchronously 
		 * returns a LightFieldPicture when given the bytes of a .lfp file.
		 */
		public static function decode(bytes:ByteArray):LightFieldPicture {
			return new LFPDecoder(bytes).picture
		}
		
		/**
		 * A wrapper/factory that simplifies the use of this class.
		 * 
		 * @param	callback	A function that is called with a LightFieldPicture when the 
		 * 						async decoding is complete. 
		 */
		public static function decodeAsync(bytes:ByteArray, callback:Function):void {
			var decoder:LFPDecoder = new LFPDecoder(bytes, false)
			decoder.addEventListener(Event.COMPLETE, function(e:*):void { callback(decoder.picture) })
		}
		
		/**
		 * Reads .lfp files and generates an abstraction for them suitable for use in Flash Player.
		 * 
		 * @param	bytes			The bytes of an entire .lfp file.
		 * @param	synchronous		Whether or not image decoding should be synchronous.  Async dispatches Event.COMPLETE.
		 */
		public function LFPDecoder(bytes:ByteArray, synchronous:Boolean = true){
			_bytes = bytes
			_synchronous = synchronous
			init()
		}
		
		/**
		 * Processes the whole ByteArray/file and creates a relevant LightFieldPicture instance.
		 */
		private function init():void {
			_imageCount = 0
			_picture = new LightFieldPicture
			readFileHeader()
			readSection(readMetadata)
			readSection(readDepths)
			
			// there seems to be no other way to know how many image sections are in the file
			while(_bytes.bytesAvailable) readSection(readImage)
		}
		
		/**
		 * Reads the very beginning of the file and does some basic validation to attempt to 
		 * avoid parsing a file that probably isn't a genuine LFP.  
		 * 
		 * @throws	VerifyError		if the file's magic numbers don't line up
		 */
		private function readFileHeader():void {
			// verify magic bytes in header
			for(var i:int = 0; i < 12; i++){
				var byte:uint = _bytes.readUnsignedByte()
				if(byte != _magic[i]) throw new VerifyError('Magic number mismatch in .lfp image header.', i)
			}
			
			// empty length
			for(i = 0; i < 4; i++) _bytes.readByte()
		}
		
		/**
		 * A generic function to read any of the sections in the file.  Sections 
		 * are much like SWF tags, or MOV container atoms, in that they have a header, 
		 * a length, and then a payload of some sort.  
		 * 
		 * The dataHandler parameter used to do something with the data payload.  
		 * It's stuck in the middle of bytes that should be handled by this section 
		 * code, so one can't really rely on the payload-specific code to handle 
		 * things like the trailing null bytes without introducting pointless 
		 * code duplication. So, pass the payload handler functions as parameters.
		 * 
		 * @param dataHandler	function dataHandler(payload:ByteArray):void
		 */
		private function readSection(dataHandler:Function):void {
			readHeader()
			var length:uint = _bytes.readUnsignedInt()
			readSHA1()
			for(var i:int = 0; i < 35; i++) _bytes.readByte() // 35 null bytes
			var data:ByteArray = new ByteArray
			_bytes.readBytes(data, 0, length)
			
			// have a more specific method handle the data
			dataHandler(data)
			
			// unspecified amount of null bytes
			do {
				if(_bytes.bytesAvailable == 0) return // this may be the last section in the whole file
				var byte:uint = _bytes.readUnsignedByte()
			} while(!byte)
			_bytes.position -= 1 // the loop neccessarily reads one extra byte
		}
		
		/**
		 * Reads the metadata section.  It contains some fairly vital information 
		 * about how the LFP is put together, such as the resolution of all of the 
		 * images and the resolution/dimensions of the depth map.  It's JSON in 
		 * plaintext.
		 * 
		 * This method introduces a dependency on FP11 since I'm using the built-in 
		 * JSON decoder instead of the one in as3corelib.  It'd be easy to switch 
		 * for compatibility if needed.
		 */
		private function readMetadata(data:ByteArray):void {
			data.position = 0
			var metadata:* = JSON.parse(data.readUTFBytes(data.length))
			_picture.metadata = metadata
		}
		
		/**
		 * Reads depth information from the depth section.  The depth information 
		 * is encoded as an array of floats, and can be mapped onto the image(s) 
		 * in the same order that BitmapData#setVector uses, so you never need to 
		 * convert these values into a 2D array, or even access them in that sense.
		 */
		private function readDepths(data:ByteArray):void {
			var len:int = data.length / 4
			var depths:Vector.<Number> = new Vector.<Number>(len, true)
			
			for(var i:int = 0; i < len; i++){
				depths[i] = data.readFloat()
			}
			_picture.depths = depths
		}
		
		/**
		 * Extracts a JPEG from the data payload of a section.
		 */
		private function readImage(data:ByteArray):void {
			if(_synchronous){
				readImageSync(data)
			} else {
				readImageAsync(data)		
			}
			_imageCount++
		}
		
		/**
		 * Use a JPEG decoder library from bytearray.org (adapted from libjpeg) to 
		 * synchronously decode the images so that the LFP decoding process can be synchronous.
		 */
		private function readImageSync(data:ByteArray):void {
			var decoder:JPEGDecoder = new JPEGDecoder
			decoder.parse(data)
			var bmpd:BitmapData = new BitmapData(decoder.width, decoder.height)
			bmpd.setVector(bmpd.rect, decoder.pixels)
			_picture.images.push(bmpd)
		}
		
		/**
		 * Use a built-in Loader to decode the JPEG instead of JPGDecoder. This is unfortunately 
		 * forced to be asynchronous, at least in FP 11.2 and older.
		 */
		private function readImageAsync(data:ByteArray):void {
			var l:Loader = new Loader
			l.contentLoaderInfo.addEventListener(Event.COMPLETE, onImageComplete)
			l.loadBytes(data)
		}
		
		/**
		 * A handler which dispatches an event for users of the async mode to listen for.
		 */ 
		private function onImageComplete(e:Event):void {
			var bmpd:BitmapData = ((e.target as LoaderInfo).content as Bitmap).bitmapData
			_picture.images.push(bmpd)
			if(_picture.images.length == _imageCount){ // all images have finished loading... asynchronously
				dispatchEvent(new Event(Event.COMPLETE))
			}
		}
		
		/**
		 * Reads any 12-byte header.  Discards it for now because I don't know what /useful/ info it provides.
		 */
		private function readHeader():void {
			for(var i:int = 0; i < 12; i++){
				var byte:uint = _bytes.readUnsignedByte()
			}
		}
		
		/**
		 * Reads the SHA-1 hash of the post-ceding data.  Doesn't use it, but it should also be in the metadata.
		 */
		private function readSHA1():void {
			for(var i:int = 0; i < 45; i++){
				var byte:uint = _bytes.readUnsignedByte()
			}
		}
		
		public function get picture():LightFieldPicture {
			return _picture
		}
	}
}