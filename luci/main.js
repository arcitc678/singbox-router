'use strict';
'require view';
'require rpc';
'require ui';

var callStatus      = rpc.declare({ object: 'singbox', method: 'status', expect: {} });
var callUpdateRules = rpc.declare({ object: 'singbox', method: 'update_rules', expect: {} });
var callUpgrade     = rpc.declare({ object: 'singbox', method: 'upgrade', expect: {} });
var callRestart     = rpc.declare({ object: 'singbox', method: 'restart', expect: {} });
var callRollback    = rpc.declare({ object: 'singbox', method: 'rollback', expect: {} });

return view.extend({
	load: function () {
		return callStatus();
	},

	render: function (st) {
		var self = this;
		var host = window.location.hostname || '192.168.0.252';
		var panelUrl = 'http://' + host + ':9090/ui/';
		var running = st && st.running == 1;

		var out = E('pre', {
			id: 'sb-out',
			style: 'margin:0;padding:12px;background:#0f1622;color:#c6ccd6;border-radius:8px;' +
			       'font-size:12.5px;line-height:1.7;min-height:60px;white-space:pre-wrap;' +
			       'word-break:break-all;max-height:220px;overflow:auto'
		}, [ '等待操作…' ]);

		function show(text) {
			out.textContent = text;
		}

		function run(fn, label) {
			show(label + ' 执行中，请稍候…');
			return fn().then(function (r) {
				if (r && r.log) {
					show(label + ' 完成\n' + r.log.replace(/\|/g, '\n'));
				} else if (r && typeof r.running !== 'undefined') {
					show(label + ' 完成，服务' + (r.running == 1 ? '运行中' : '未运行') +
					     (r.version ? '，版本 ' + r.version : ''));
				} else {
					show(label + ' 完成');
				}
				if (label.indexOf('重启') >= 0 || label.indexOf('升级') >= 0 || label.indexOf('回滚') >= 0)
					setTimeout(function () { location.reload(); }, 2500);
			}).catch(function (e) {
				show(label + ' 失败：' + (e && e.message ? e.message : e));
			});
		}

		function btn(label, cls, fn) {
			return E('button', {
				'class': 'btn cbi-button ' + (cls || ''),
				'style': 'margin-right:8px;margin-bottom:8px',
				'click': function (ev) { ev.preventDefault(); run(fn, label); }
			}, [ label ]);
		}

		var statusLine = E('div', { style: 'margin-bottom:14px;font-size:13.5px' }, [
			E('span', {
				style: 'display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:8px;' +
				       'background:' + (running ? '#22b573' : '#b4443c')
			}),
			'内核 ' + (st && st.version ? st.version : '未知') +
			' · ' + (running ? '运行中' : '未运行')
		]);

		return E('div', {}, [
			E('h2', {}, [ 'Sing-Box' ]),
			E('div', { 'class': 'cbi-section' }, [
				statusLine,
				E('div', { style: 'margin-bottom:12px' }, [
					btn('更新 geosite/geoip', '', callUpdateRules),
					btn('升级内核', '', callUpgrade),
					btn('重启服务', '', callRestart),
					btn('回滚到 homeproxy', 'cbi-button-negative', callRollback)
				]),
				out
			]),
			E('h2', { style: 'margin-top:24px' }, [ '面板' ]),
			E('div', { style: 'margin-bottom:8px;font-size:13px;color:#666' }, [
				E('a', { href: panelUrl, target: '_blank' }, panelUrl), ' （新窗口打开）'
			]),
			E('iframe', {
				src: panelUrl,
				style: 'width:100%;height:calc(100vh - 420px);min-height:520px;' +
				       'border:1px solid #ddd;border-radius:8px;background:#101827'
			})
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
