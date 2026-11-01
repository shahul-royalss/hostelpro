/// The PG's map pin (round 6): the owner drops it on a map, tenants see it and open it in
/// Google Maps.
///
/// SATELLITE FIRST (the owner's words: "the map has to be satellite mode"). The imagery is Esri
/// World Imagery with Esri's road and place-name layers on top, so a gate can be found from the
/// air and the street still has a name; a button switches to the OpenStreetMap street map. No API
/// key either way: flutter_map fetches the tiles with this app's package name as the User-Agent,
/// and each source's attribution is drawn on the map as its terms ask. "Open in Google Maps" is a
/// geo: intent to the Google Maps APP (data/device/apps_launcher.dart), never a browser.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/tokens.dart';
import '../../data/device/apps_launcher.dart';
import '../../data/device/signup_device.dart';
import '../../shared/glass/glass.dart';
import '../signup/signup_widgets.dart' show askInWords;
import 'form_parts.dart';

const _userAgent = 'com.nivorasr.app';
const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';
const _imagery = '$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}';
const _roads = '$_esri/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';
const _places = '$_esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
const _street = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// The middle of India, for a PG with no pin and a phone that will not say where it is.
const _india = LatLng(20.5937, 78.9629);

/// False in widget tests, which have no network: the map draws without tiles.
final mapTilesProvider = Provider<bool>((_) => true);

TileLayer _layer(String url) =>
    TileLayer(urlTemplate: url, userAgentPackageName: _userAgent, maxNativeZoom: 19);

/// The tiles under the pin: satellite with roads and place names, or the street map.
List<Widget> _tileLayers(WidgetRef ref, {bool satellite = true, bool roads = true}) {
  if (!ref.watch(mapTilesProvider)) return const [];
  if (!satellite) {
    return [
      _layer(_street),
      const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
    ];
  }
  return [
    _layer(_imagery),
    if (roads) _layer(_roads),
    _layer(_places),
    const SimpleAttributionWidget(
      source: Text('Esri, Maxar, Earthstar Geographics, and the GIS User Community'),
    ),
  ];
}

/// Opens the full-screen picker. Null when the owner backs out.
Future<LocationFix?> pickPinOnMap(BuildContext context, {double? latitude, double? longitude}) {
  return Navigator.of(context).push<LocationFix>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MapPinPickerScreen(
        start: latitude != null && longitude != null ? LatLng(latitude, longitude) : null,
      ),
    ),
  );
}

/// Drag the map until the pin sits on the PG's gate, then "Use this spot".
class MapPinPickerScreen extends ConsumerStatefulWidget {
  const MapPinPickerScreen({super.key, this.start});

  /// The pin already saved, if any.
  final LatLng? start;

  @override
  ConsumerState<MapPinPickerScreen> createState() => _MapPinPickerScreenState();
}

class _MapPinPickerScreenState extends ConsumerState<MapPinPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.start ?? _india;
  bool _locating = false;
  bool _satellite = true;
  String? _note;

  Future<void> _myLocation() async {
    setState(() {
      _locating = true;
      _note = null;
    });
    final outcome = await ref.read(deviceLocatorProvider).locate(
          explain: () => askInWords(
            context,
            title: context.tr('Use your location?'),
            message: context.tr('Apnivaas asks your phone where you are once, to move the map '
                'there. You can still drag the pin anywhere.'),
          ),
        );
    if (!mounted) return;
    setState(() {
      _locating = false;
      switch (outcome) {
        case LocationFix(:final latitude, :final longitude):
          _center = LatLng(latitude, longitude);
          _map.move(_center, 18);
        case LocationSkipped():
          break;
        case LocationUnavailable(:final message):
          _note = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Set the pin on the map'))),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.start == null ? 4.5 : 18,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, _) => _center = camera.center,
            ),
            children: _tileLayers(ref, satellite: _satellite),
          ),
          // The pin stays in the middle; the map moves under it. Its point is the bottom tip.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Icon(Icons.location_on_rounded, size: 48, color: t.colorScheme.error),
              ),
            ),
          ),
          Positioned(
            left: Space.md,
            right: Space.md,
            top: Space.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FlatSurface(
                    borderRadius: Radii.rSurface,
                    padding: const EdgeInsets.all(Space.sm),
                    child: Text(
                      context.tr('Drag the map until the pin sits on your PG gate. '
                          'Pinch to zoom.'),
                      style: t.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                // Satellite first; the street map is one tap away for finding the road.
                FloatingActionButton.small(
                  key: const Key('map-layer'),
                  heroTag: null,
                  tooltip: context.tr(_satellite ? 'Street map' : 'Satellite'),
                  onPressed: () => setState(() => _satellite = !_satellite),
                  child: Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt_rounded),
                ),
              ],
            ),
          ),
          Positioned(
            left: Space.md,
            right: Space.md,
            bottom: Space.md,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_note != null) ...[
                    FlatSurface(
                      borderRadius: Radii.rSurface,
                      padding: const EdgeInsets.all(Space.sm),
                      child: FormNote(_note!, tone: FormNoteTone.warning),
                    ),
                    const SizedBox(height: Space.xs),
                  ],
                  FilledButton.tonalIcon(
                    key: const Key('map-my-location'),
                    onPressed: _locating ? null : _myLocation,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: IconSize.sm,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: IconSize.md),
                    label: Text(context.tr('Go to where I am')),
                  ),
                  const SizedBox(height: Space.xs),
                  BusyFilledButton(
                    key: const Key('map-use-spot'),
                    label: 'Use this spot',
                    onPressed: () => Navigator.of(context)
                        .pop(LocationFix(_center.latitude, _center.longitude)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The PG page's location card: a small satellite map with the pin, and "Open in Google Maps".
class PgLocationCard extends ConsumerWidget {
  const PgLocationCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.name,
    this.place,
  });

  final double latitude;
  final double longitude;
  final String name;
  final String? place;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final opened = await ref
        .read(appsLauncherProvider)
        .openMap(latitude: latitude, longitude: longitude, label: name);
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.tr('Install Google Maps to see directions.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final pin = LatLng(latitude, longitude);
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.surface)),
            child: SizedBox(
              height: 170,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: pin,
                  initialZoom: 17,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  onTap: (_, _) => _open(context, ref),
                ),
                children: [
                  ..._tileLayers(ref, roads: false),
                  MarkerLayer(markers: [
                    Marker(
                      point: pin,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on_rounded, size: 40, color: t.colorScheme.error),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    place == null || place!.isEmpty ? name : place!,
                    style: t.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: Space.sm),
                FilledButton.tonalIcon(
                  key: const Key('pg-open-map'),
                  // The theme's buttons are full width; this one shares its row with the place.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _open(context, ref),
                  icon: const Icon(Icons.directions_rounded, size: IconSize.md),
                  label: Text(context.tr('Open in Google Maps')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
