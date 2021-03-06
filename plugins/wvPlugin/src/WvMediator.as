package
{
	import com.kaltura.KalturaClient;
	import com.kaltura.kdpfl.model.MediaProxy;
	import com.kaltura.kdpfl.model.SequenceProxy;
	import com.kaltura.kdpfl.model.ServicesProxy;
	import com.kaltura.kdpfl.model.type.EnableType;
	import com.kaltura.kdpfl.model.type.NotificationType;
	import com.kaltura.kdpfl.model.type.SequenceContextType;
	import com.kaltura.kdpfl.model.type.StreamerType;
	import com.kaltura.kdpfl.plugin.WVLoadTrait;
	import com.kaltura.kdpfl.plugin.WVPluginInfo;
	import com.kaltura.kdpfl.view.controls.BufferAnimationMediator;
	import com.kaltura.kdpfl.view.media.KMediaPlayerMediator;
	import com.kaltura.vo.KalturaFlavorAsset;
	import com.kaltura.vo.KalturaMediaEntry;
	import com.kaltura.vo.KalturaWidevineFlavorAsset;
	import com.widevine.WvNetConnection;
	
	import flash.events.Event;
	import flash.events.NetStatusEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.utils.Timer;
	import flash.utils.setTimeout;
	
	import org.osmf.events.MediaElementEvent;
	import org.osmf.events.MediaErrorEvent;
	import org.osmf.traits.MediaTraitType;
	import org.puremvc.as3.interfaces.INotification;
	import org.puremvc.as3.patterns.mediator.Mediator;
	
	public class WvMediator extends Mediator
	{
		public static const NAME:String = "WvMediator";
		public static const NO_WV_BROWSER_PLUGIN:String = "noWidevineBrowserPlugin";
		/**
		 * indicates the next flavor should start playback from this position 
		 */		
		private var _pendingSeekTo:Number = 0;
		/**
		 * last playhead position 
		 */		
		private var _lastPlayhead:Number;
		/**
		 * indicates next play should call wvNetstrea.replay 
		 */		
		private var _isReplay:Boolean;	
		/**
		 * indicates if the player is currently playing wv netstream 
		 */		
		private var _isWv:Boolean;		
		/**
		 * after wv netstream has already reported  netstream complete we need to ignore all doSeek requests
		 */		
		private var _ignoreSeek:Boolean;
		
		private var _wvPluginInfo:WVPluginInfo;

		private var _wvPluginCode:widevinePluginCode;
		
		private var _bufferLength:Number = 0;
		private var _mediaProxy:MediaProxy;
		
		private var _endOfStreamTimer:Timer;
		
		public function WvMediator(wvPluginCode:widevinePluginCode, wvPI:WVPluginInfo)
		{
			_wvPluginCode = wvPluginCode;
			_wvPluginInfo = wvPI;
			_wvPluginInfo.addEventListener(WVPluginInfo.WVMEDIA_ELEMENT_CREATED, onWVElementCreated, false, 0, true);	
			super(NAME);
		}
		
		override public function onRegister():void
		{
			_mediaProxy = facade.retrieveProxy(MediaProxy.NAME) as MediaProxy;
			super.onRegister();
		}
		
		override public function listNotificationInterests():Array {
			return [NotificationType.DO_SEEK,
					NotificationType.MEDIA_ELEMENT_READY,
					NotificationType.PLAYER_UPDATE_PLAYHEAD,
					NotificationType.PLAYER_PLAY_END,
					NotificationType.PLAYER_PLAYED,
					NotificationType.DO_PLAY,
					NotificationType.BUFFER_PROGRESS,
					NotificationType.CHANGE_MEDIA,
					NotificationType.DO_PAUSE,
					NO_WV_BROWSER_PLUGIN];
		}
		
		override public function handleNotification(note:INotification):void {
			switch (note.getName()) 
			{
				case NotificationType.DO_SEEK:
					if (!_ignoreSeek && _isWv)
					{
						var seekTo:Number = note.getBody() as Number;
						if(_wvPluginInfo && _wvPluginInfo.wvMediaElement && _wvPluginInfo.wvMediaElement.netStream)
						{	
							//workaround to fix seek issue
							setTimeout(seekWvStream, 1, seekTo);
						}
					}
						
					break;
				
				case NotificationType.MEDIA_ELEMENT_READY:	
					//get flavor asset ID
					if (!(facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy).vo.isInSequence && _mediaProxy.vo.deliveryType==StreamerType.HTTP)
					{
						var flavors:Array = _mediaProxy.vo.kalturaMediaFlavorArray;
						if (flavors && flavors.length)
						{
							var wvAssetId:String;
							if (_mediaProxy.vo.selectedFlavorId && flavors.length > 1)
							{
								for (var i:int = 0; i<flavors.length; i++)
								{
									var flavor:KalturaFlavorAsset = flavors[i] as KalturaFlavorAsset;
									if (flavor.id == _mediaProxy.vo.selectedFlavorId)
									{
										if (flavor is KalturaWidevineFlavorAsset)
										{
											wvAssetId = flavor.id;
											
										}
										break;
									}
								}
							}
								//if we don't have selected flavor ID we are playing the first one
							else if (flavors[0] is KalturaWidevineFlavorAsset)
							{
								wvAssetId = (flavors[0] as KalturaWidevineFlavorAsset).id;
							}
							
							if (wvAssetId)
							{
								_isWv = true;
								var kc:KalturaClient = (facade.retrieveProxy(ServicesProxy.NAME) as ServicesProxy).kalturaClient;
								var emmUrl:String = kc.protocol + kc.domain + "/api_v3/index.php?service=widevine_widevinedrm&action=getLicense&format=widevine&flavorAssetId=" + wvAssetId + "&ks=" +kc.ks;
								ExternalInterface.call("WVSetEmmURL", emmUrl);

								
							}
							else
							{
								_isWv = false;
							}
							
						}
						else
						{
							_isWv = false;
						}
					}
	

					break;
	
				
				case NotificationType.PLAYER_UPDATE_PLAYHEAD:
					//in case we switch flavors we want to save last position
					if (_isWv && !(facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy).vo.isInSequence)
						_lastPlayhead = note.getBody() as Number;
					break;
					
				case NotificationType.PLAYER_PLAY_END:
					if (_isWv)
						_isReplay = true;
					break;
				
				case NotificationType.DO_PLAY:
					if (_endOfStreamTimer && !_endOfStreamTimer.running)
					{
						_endOfStreamTimer.start();
					}
					else if (_isWv && _isReplay)
					{
						_wvPluginInfo.wvMediaElement.netStream.replay();
						_isReplay = false;
					}
					break;
				
				case NotificationType.PLAYER_PLAYED:
					if (_isWv && !(facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy).vo.isInSequence)
					{
						var playerMediator:KMediaPlayerMediator = facade.retrieveMediator(KMediaPlayerMediator.NAME) as KMediaPlayerMediator;
						//workaround for wv bug, netstream reports end before actual end
						playerMediator.ignorePlaybackComplete = true;
					}
					break;
				
				case NotificationType.BUFFER_PROGRESS:
					_bufferLength = note.getBody().newTime;
					break;
				
				case NotificationType.CHANGE_MEDIA:
					_isReplay = false;
					if (_endOfStreamTimer && _endOfStreamTimer.running)
					{
						_ignoreSeek = false;
						_endOfStreamTimer.removeEventListener(TimerEvent.TIMER_COMPLETE, endOfClip);
						_endOfStreamTimer.stop();
						_endOfStreamTimer = null;
						_wvPluginInfo.wvMediaElement.netStream.pause();
					}
					var kmediaMediator:KMediaPlayerMediator = facade.retrieveMediator(KMediaPlayerMediator.NAME) as KMediaPlayerMediator;
					if (_mediaProxy.vo.isFlavorSwitching)
						_pendingSeekTo = _lastPlayhead;
					break;
				
				case NotificationType.DO_PAUSE:
					if (_endOfStreamTimer && _endOfStreamTimer.running)
					{
						_endOfStreamTimer.stop();
					}
					break;
				
				case NO_WV_BROWSER_PLUGIN:
					sendNotification( NotificationType.ALERT , {message: _wvPluginCode.alert_missing_plugin, title: _wvPluginCode.alert_title} );
					sendNotification(NotificationType.ENABLE_GUI, {guiEnabled: false, enableType : EnableType.CONTROLS});
					break;
				
			}
		}
		
		public function seekWvStream(seekTo:Number): void
		{
			var maxSeek:Number = (_mediaProxy.vo.entry as KalturaMediaEntry).duration - _bufferLength;
			//can't seek to complete end
			_wvPluginInfo.wvMediaElement.netStream.seek( Math.min(seekTo, maxSeek));
		}
		
		private function onWVElementCreated(e : Event) : void
		{
			if (_mediaProxy.vo.entry && _mediaProxy.vo.entry is KalturaMediaEntry)
			{
				_wvPluginInfo.wvMediaElement.w = (_mediaProxy.vo.entry as KalturaMediaEntry).width;
				_wvPluginInfo.wvMediaElement.h = (_mediaProxy.vo.entry as KalturaMediaEntry).height;
				
			}
			_wvPluginInfo.wvMediaElement.addEventListener(NetStatusEvent.NET_STATUS, onNetStatus, false, 0, true);
			_wvPluginInfo.wvMediaElement.addEventListener(MediaElementEvent.TRAIT_ADD, onTraitAdd, false, 0, true);
		}
		
		private function onTraitAdd(e: MediaElementEvent) : void
		{
			if (e.traitType == MediaTraitType.SEEK)
			{
				//seek to previous flavor last playhead position
				if (_pendingSeekTo)
				{
					seekWvStream(_pendingSeekTo);
					_pendingSeekTo = 0;
				}
			//	_wvPluginInfo.wvMediaElement.removeEventListener(MediaElementEvent.TRAIT_ADD, onTraitAdd);
			}
			else if (e.traitType == MediaTraitType.LOAD)
			{
				(_wvPluginInfo.wvMediaElement.getTrait(MediaTraitType.LOAD) as WVLoadTrait).drmNetConnection.addEventListener(WvNetConnection.DO_CONNECT_FAILED, onConnectFail, false, 0, true);
			}
			
		}
		
		private function onConnectFail(e: Event) : void
		{
			var errEvent:MediaErrorEvent = new MediaErrorEvent(MediaErrorEvent.MEDIA_ERROR);
			_mediaProxy.vo.media.dispatchEvent(errEvent);
		}
		
		/**
		 * wvMediaElement bubbles up all netstatus event. Display proper KDP alerts accordingly.
		 * @param e
		 * 
		 */		
		private function onNetStatus(e: NetStatusEvent):void
		{
			trace ("widevinePlugin > onNetStatus:" ,e.info.code, e.info.details);
			var err:String;
			
			switch (e.info.code)
			{	
				case "NetStream.Wv.EmmError":
					err = _wvPluginCode.alert_emm_error;
					break;
				case "NetStream.Wv.EmmExpired":
					err = _wvPluginCode.alert_emm_expired;
					break;
				
				case "NetStream.Wv.LogError":
					err = _wvPluginCode.alert_log_error;
					if (e.info.details)
						err = err.replace("{0}", e.info.details);
					break;
				
				case "NetStream.Wv.EmmFailed":
					err = _wvPluginCode.alert_emm_falied;
					break;
				
				case "NetStream.Wv.DcpStop":
					err = _wvPluginCode.alert_dcp_stop;
					break;
				
				case "NetStream.Wv.DcpAlert":
					sendNotification( NotificationType.ALERT , {message: _wvPluginCode.alert_dcp_alert, title: _wvPluginCode.warning_title} );
					break;
				
				// workaround- playComplete is sent before stream ended.
				case "NetStream.Play.Complete":
					_ignoreSeek = true;
					_endOfStreamTimer = new Timer(1000, Math.ceil(_wvPluginInfo.wvMediaElement.netStream.bufferLength));
					_endOfStreamTimer.addEventListener(TimerEvent.TIMER_COMPLETE, endOfClip, false, 0, true);
					_endOfStreamTimer.start();
					break;
				
				/*	case "NetStream.Buffer.Empty":
				
				break;
				
				case "NetStream.Seek.Notify":
				
				break;
				
				case "NetStream.Buffer.Full":
				
				break;
				
				case "NetStream.Play.Start" :
				
				break;
				
				case "NetStream.Wv.EmmSuccess":
				
				break;*/
			}
			
			if (err)
			{
				sendNotification( NotificationType.ALERT , {message: err, title: _wvPluginCode.alert_title} );
				sendNotification( NotificationType.DO_PAUSE);
				sendNotification(NotificationType.ENABLE_GUI, {guiEnabled: false, enableType : EnableType.CONTROLS});
				(facade.retrieveMediator(BufferAnimationMediator.NAME) as BufferAnimationMediator).spinner.visible = false;
				
			}
		}
		
		/**
		 * this workaround fixes widevine known issue: stream reports complete before its time. 
		 * 
		 */		
		private function endOfClip(e:TimerEvent = null) : void
		{
			sendNotification(NotificationType.PLAYBACK_COMPLETE, {context: SequenceContextType.MAIN});
			_ignoreSeek = false;
			_endOfStreamTimer.removeEventListener(TimerEvent.TIMER_COMPLETE, endOfClip);
			_endOfStreamTimer = null;
		}
		
	}
}