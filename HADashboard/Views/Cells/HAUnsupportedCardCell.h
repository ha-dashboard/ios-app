#import "HABaseEntityCell.h"

/// Placeholder cell shown in place of a Lovelace card type HA Dashboard
/// cannot render natively (an unrecognized `type`, an unmapped `custom:*`
/// card, or a custom card built entirely of sub-items this app doesn't read).
///
/// Produced by HALovelaceParser when a card yields zero usable entities and
/// the "Show Unsupported Cards" developer toggle is enabled (default YES).
/// Displays the card's raw Lovelace type string so a user can report exactly
/// which card types are missing, without crashing on malformed configs and
/// without ever showing an entity (there isn't one).
@interface HAUnsupportedCardCell : HABaseEntityCell

@end
