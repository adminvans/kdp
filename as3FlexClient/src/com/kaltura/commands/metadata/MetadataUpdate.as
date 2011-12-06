package com.kaltura.commands.metadata
{
	import com.kaltura.delegates.metadata.MetadataUpdateDelegate;
	import com.kaltura.net.KalturaCall;

	public class MetadataUpdate extends KalturaCall
	{
		public var filterFields : String;
		/**
		 * @param id int
		 * @param xmlData String
		 * @param version int
		 **/
		public function MetadataUpdate( id : int,xmlData : String = null,version : int=int.MIN_VALUE )
		{
			service= 'metadata_metadata';
			action= 'update';

			var keyArr : Array = new Array();
			var valueArr : Array = new Array();
			var keyValArr : Array = new Array();
			keyArr.push('id');
			valueArr.push(id);
			keyArr.push('xmlData');
			valueArr.push(xmlData);
			keyArr.push('version');
			valueArr.push(version);
			applySchema(keyArr, valueArr);
		}

		override public function execute() : void
		{
			setRequestArgument('filterFields', filterFields);
			delegate = new MetadataUpdateDelegate( this , config );
		}
	}
}
