'use strict';
'require view';

return view.extend({
	render: function () {
		var host = window.location.hostname || '192.168.0.252';
		var url = 'http://' + host + ':9090/ui/';
		return E('div', {}, [
			E('div', { style: 'margin-bottom:10px;color:#666;font-size:13px' }, [
				'面板地址：',
				E('a', { href: url, target: '_blank' }, url),
				' （新窗口打开）'
			]),
			E('iframe', {
				src: url,
				style: 'width:100%;height:calc(100vh - 190px);border:1px solid #ddd;border-radius:8px;background:#101827'
			})
		]);
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
