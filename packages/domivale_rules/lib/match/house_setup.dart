import '../board/cell.dart';
import '../cards/card_kind.dart';
import 'banner.dart';

/// Everything decided about one house before the match starts. Part of the
/// match header, so a replay deals the same opening hand.
class HouseSetup {
  HouseSetup({
    required this.name,
    required this.banner,
    required this.heart,
    required this.chosenBasic,
    this.bannerBasic,
  }) {
    if (!chosenBasic.isBasic) {
      throw ArgumentError.value(
          chosenBasic, 'chosenBasic', 'the chosen opening card is a basic');
    }
    if (banner == Banner.expander) {
      if (bannerBasic == null || !bannerBasic!.isBasic) {
        throw ArgumentError.value(bannerBasic, 'bannerBasic',
            'an Expander names the basic card its banner gives');
      }
    } else if (bannerBasic != null) {
      throw ArgumentError.value(bannerBasic, 'bannerBasic',
          'only an Expander chooses its banner card');
    }
  }

  /// How the house is spoken of: "the Lake House".
  final String name;

  final Banner banner;

  /// Where the house's first city stands.
  final Cell heart;

  /// The basic card the house chose for its opening hand, from the terrain
  /// around its heart.
  final CardKind chosenBasic;

  /// The Expander's banner card: one more basic of its choice. Null for the
  /// other banners.
  final CardKind? bannerBasic;

  /// The card the banner adds to the opening hand.
  CardKind get bannerCard => banner.card ?? bannerBasic!;

  /// A Farm, the chosen basic and the banner card, in that order.
  List<CardKind> get openingHand => [CardKind.farm, chosenBasic, bannerCard];
}
