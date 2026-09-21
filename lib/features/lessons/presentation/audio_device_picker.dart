import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show MediaDevice;

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../data/live_media.dart';

/// Which microphone and which speaker the room uses.
///
/// The app took whatever the operating system called the default and offered
/// no way to see which that was. That is fine until the default is not a
/// microphone: a virtual audio cable, a voice changer or a "meeting
/// assistant" installs itself in front of the real device, and whatever it
/// does to the signal is mixed in before the app ever sees it — so the whole
/// room hears it and the person speaking cannot tell.
///
/// Desktop only. `Hardware.selectAudioInput` refuses on the browser and on
/// phones, where the input follows the system's own choice.
Future<void> showAudioDevicePicker(
  BuildContext context,
  LiveMediaSession media,
) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _Picker(media: media),
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.media});

  final LiveMediaSession media;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  List<MediaDevice> _inputs = const [];
  List<MediaDevice> _outputs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final inputs = await widget.media.audioInputs();
      final outputs = await widget.media.audioOutputs();
      if (!mounted) return;
      setState(() {
        _inputs = inputs;
        _outputs = outputs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Qurilmalar ro‘yxatini o‘qib bo‘lmadi: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickInput(MediaDevice device) async {
    await widget.media.selectAudioInput(device);
    if (mounted) setState(() {});
  }

  Future<void> _pickOutput(MediaDevice device) async {
    await widget.media.selectAudioOutput(device);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Ovoz qurilmalari', style: HkType.pageTitle),
                  ),
                  IconButton(
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: HkColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tanlangan mikrofonni darsni to‘xtatmasdan almashtirsa '
                'bo‘ladi — xona darhol yangisini eshitadi.',
                style: HkType.muted,
              ),
              const SizedBox(height: 18),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? Text(_error!, style: HkType.body)
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Section(
                                  title: 'Mikrofon',
                                  icon: Icons.mic_rounded,
                                  devices: _inputs,
                                  selected: widget.media.audioInput,
                                  onPick: _pickInput,
                                ),
                                const SizedBox(height: 18),
                                _Section(
                                  title: 'Dinamik',
                                  icon: Icons.volume_up_rounded,
                                  devices: _outputs,
                                  selected: widget.media.audioOutput,
                                  onPick: _pickOutput,
                                ),
                              ],
                            ),
                          ),
              ),
              const SizedBox(height: 16),
              // The reason this screen exists, said once. A teacher looking
              // at a list of device names has no way to know that "CABLE
              // Input" is not a microphone.
              Text(
                'Agar tanlangan qurilma nomida "Virtual", "Cable", "Voice" '
                'kabi so‘zlar bo‘lsa — bu haqiqiy mikrofon emas, balki '
                'oradagi dastur. Ovozni o‘zgartirib yuboradi va xonadagi '
                'hamma shuni eshitadi. Mikrofonni o‘z nomi bilan tanlang.',
                style: HkType.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.devices,
    required this.selected,
    required this.onPick,
  });

  final String title;
  final IconData icon;
  final List<MediaDevice> devices;
  final MediaDevice? selected;
  final ValueChanged<MediaDevice> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: HkColors.textSecondary),
            const SizedBox(width: 8),
            Text(title, style: HkType.sectionTitle),
          ],
        ),
        const SizedBox(height: 10),
        if (devices.isEmpty)
          Text('Bu kompyuterda topilmadi', style: HkType.muted)
        else
          for (final device in devices) ...[
            _DeviceRow(
              device: device,
              chosen: device.deviceId == selected?.deviceId,
              onTap: () => onPick(device),
            ),
            if (device != devices.last) const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.chosen,
    required this.onTap,
  });

  final MediaDevice device;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: chosen ? const Color(0x1AD4E94C) : const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(HkRadius.cardSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                chosen
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: chosen ? HkColors.lime : HkColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  // Some drivers report an empty label until permission has
                  // been granted; the id is at least something to tell two
                  // nameless rows apart by.
                  device.label.isEmpty ? device.deviceId : device.label,
                  style: HkType.body.copyWith(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
