import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/nekosim_strings.dart';
import '../services/nekosim_asset_service.dart';
import '../services/nekosim_cloud_service.dart';
import '../theme/app_theme.dart';
import '../widgets/nekosim_glass.dart';
import '../widgets/styled_header_scaffold.dart';

class NekoSimCloudPage extends StatefulWidget {
  const NekoSimCloudPage({super.key});

  @override
  State<NekoSimCloudPage> createState() => _NekoSimCloudPageState();
}

class _NekoSimCloudPageState extends State<NekoSimCloudPage> {
  final _cloud = NekoSimCloudService();
  final _assets = NekoSimAssetService();
  String _message = '';
  bool _busy = false;

  late final TextEditingController _serverUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _remindDays;
  late final TextEditingController _botToken;
  late final TextEditingController _chatId;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;
  late final TextEditingController _smtpUser;
  late final TextEditingController _smtpPass;
  late final TextEditingController _smtpFrom;
  late final TextEditingController _smtpTo;

  @override
  void initState() {
    super.initState();
    final c = _cloud.config;
    _serverUrl = TextEditingController(text: c.serverUrl);
    _apiKey = TextEditingController(text: c.apiKey);
    _remindDays = TextEditingController(text: '${c.remindDays}');
    _botToken = TextEditingController(text: c.botToken);
    _chatId = TextEditingController(text: c.chatId);
    _smtpHost = TextEditingController(text: c.smtpHost);
    _smtpPort = TextEditingController(text: '${c.smtpPort}');
    _smtpUser = TextEditingController(text: c.smtpUser);
    _smtpPass = TextEditingController(text: c.smtpPass);
    _smtpFrom = TextEditingController(text: c.smtpFrom);
    _smtpTo = TextEditingController(text: c.smtpTo);
    _cloud.init().then((_) {
      if (!mounted) return;
      setState(() {
        final cc = _cloud.config;
        _serverUrl.text = cc.serverUrl;
        _apiKey.text = cc.apiKey;
        _remindDays.text = '${cc.remindDays}';
        _botToken.text = cc.botToken;
        _chatId.text = cc.chatId;
        _smtpHost.text = cc.smtpHost;
        _smtpPort.text = '${cc.smtpPort}';
        _smtpUser.text = cc.smtpUser;
        _smtpPass.text = cc.smtpPass;
        _smtpFrom.text = cc.smtpFrom;
        _smtpTo.text = cc.smtpTo;
      });
    });
  }

  @override
  void dispose() {
    // Flush unsaved text edits; controller values are read synchronously
    // before the controllers are disposed below.
    _saveConfig();
    for (final c in [
      _serverUrl,
      _apiKey,
      _remindDays,
      _botToken,
      _chatId,
      _smtpHost,
      _smtpPort,
      _smtpUser,
      _smtpPass,
      _smtpFrom,
      _smtpTo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final c = _cloud.config;
    c.serverUrl = _serverUrl.text.trim();
    c.apiKey = NekoSimCloudService.cleanApiKey(_apiKey.text);
    c.remindDays = int.tryParse(_remindDays.text.trim()) ?? 7;
    c.botToken = _botToken.text.trim();
    c.chatId = _chatId.text.trim();
    c.smtpHost = _smtpHost.text.trim();
    c.smtpPort = int.tryParse(_smtpPort.text.trim()) ?? 465;
    c.smtpUser = _smtpUser.text.trim();
    c.smtpPass = _smtpPass.text;
    c.smtpFrom = _smtpFrom.text.trim();
    c.smtpTo = _smtpTo.text.trim();
    await _cloud.persist();
  }

  Future<void> _run(Future<CloudResult> Function() op, {String? okText}) async {
    final t = NekoSimStrings.of(context);
    setState(() => _busy = true);
    CloudResult res;
    try {
      await _saveConfig();
      res = await op();
    } catch (e) {
      res = CloudResult(false, e.toString());
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = res.ok ? (okText ?? res.message) : '${t.failed}: ${res.message}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = NekoSimStrings.of(context);
    final theme = Theme.of(context);
    final c = _cloud.config;

    return StyledHeaderScaffold(
      title: t.cloudReminders,
      body: GlassAmbientBackground(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassSection(
                title: t.cloudReminders,
                children: [
                  SwitchListTile(
                    title: Text(t.enableCloud),
                    value: c.enabled,
                    onChanged: (v) async {
                      setState(() => c.enabled = v);
                      await _cloud.persist();
                    },
                  ),
                  SwitchListTile(
                    title: Text(t.autoSync),
                    subtitle: Text(t.autoSyncHint),
                    value: c.autoSync,
                    onChanged: (v) async {
                      setState(() => c.autoSync = v);
                      await _cloud.persist();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GlassSection(
                title: t.serverUrl,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        _field(_serverUrl, t.serverUrl, Icons.dns_rounded,
                            keyboard: TextInputType.url),
                        _field(_apiKey, t.apiKey, Icons.key_rounded,
                            mono: true),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => _cloud.register(),
                                            okText: t.keyGenerated)
                                        .then((_) => setState(() => _apiKey
                                            .text = _cloud.config.apiKey)),
                                icon: const Icon(Icons.vpn_key_rounded,
                                    size: 18),
                                label: Text(t.generateKey),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        final key =
                                            NekoSimCloudService.cleanApiKey(
                                                _apiKey.text);
                                        if (key.isNotEmpty) {
                                          Clipboard.setData(
                                              ClipboardData(text: key));
                                          setState(
                                              () => _message = t.copied);
                                        }
                                      },
                                icon:
                                    const Icon(Icons.copy_rounded, size: 18),
                                label: Text(t.copy),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => _cloud.status(),
                                        okText: t.connected),
                                child: Text(t.testConnection),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                          () async => _cloud
                                              .sync(await _assets.getAll()),
                                          okText: t.synced,
                                        ),
                                child: Text(t.syncNow),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field(_remindDays, t.remindDays,
                            Icons.notifications_active_outlined,
                            keyboard: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GlassSection(
                title: t.telegramSection,
                children: [
                  SwitchListTile(
                    title: Text(t.enableTelegram),
                    value: c.telegramEnabled,
                    onChanged: (v) async {
                      setState(() => c.telegramEnabled = v);
                      await _cloud.persist();
                    },
                  ),
                  if (c.telegramEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          _field(_botToken, t.botToken,
                              Icons.smart_toy_outlined,
                              obscure: true, mono: true),
                          _field(_chatId, t.chatId, Icons.chat_outlined),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async => _cloud
                                      .testTelegram(await _assets.getAll())),
                              child: Text(t.testTelegram),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              GlassSection(
                title: t.emailSection,
                children: [
                  SwitchListTile(
                    title: Text(t.enableEmail),
                    value: c.emailEnabled,
                    onChanged: (v) async {
                      setState(() => c.emailEnabled = v);
                      await _cloud.persist();
                    },
                  ),
                  if (c.emailEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: _field(_smtpHost, t.smtpHost,
                                      Icons.dns_outlined)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _field(_smtpPort, t.smtpPort,
                                      Icons.numbers_rounded,
                                      keyboard: TextInputType.number)),
                            ],
                          ),
                          _field(_smtpUser, t.smtpUser,
                              Icons.person_outline_rounded),
                          _field(_smtpPass, t.smtpPass, Icons.password_rounded,
                              obscure: true),
                          _field(_smtpFrom, t.smtpFrom, Icons.outbox_rounded),
                          _field(
                              _smtpTo, t.smtpTo, Icons.move_to_inbox_rounded),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async => _cloud
                                      .testEmail(await _assets.getAll())),
                              child: Text(t.testEmail),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () async => _cloud.checkNow(await _assets.getAll()),
                          okText: t.checkTriggered,
                        ),
                icon: const Icon(Icons.alarm_on_rounded),
                label: Text(t.checkNow),
              ),
              const SizedBox(height: 12),
              if (_busy) const Center(child: CircularProgressIndicator()),
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _message,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              Text(
                t.cloudHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                t.secretsWarning,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    bool obscure = false,
    bool mono = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        style: mono ? AppTheme.mono(const TextStyle(fontSize: 14)) : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          isDense: true,
          filled: true,
          fillColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onEditingComplete: _saveConfig,
      ),
    );
  }
}
