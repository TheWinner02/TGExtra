#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define kAccountUpdateOnlineStatus 1713919532
#define kMessagesSetTypingAction 1486110434
#define kMessagesReadHistory 238054714
#define kStoriesReadStories -1521034552
#define kGetSponsoredMessages -1680673735
#define kSendScreenshotNotification -1589618665
#define kMessagesReadMessageContents 917472119

#define kActionIDTyping                 381645902                       // .sendMessageTypingAction
#define kActionIDRecordingVideo        -1584933265                     // .sendMessageRecordVideoAction
#define kActionIDUploadingVideo        -378127636                      // .sendMessageUploadVideoAction
#define kActionIDRecordingAudio        -718310409                      // .sendMessageRecordAudioAction
#define kActionIDUploadingVoice        -212740181                      // .sendMessageUploadAudioAction
#define kActionIDUploadingPhoto        -774682074                      // .sendMessageUploadPhotoAction
#define kActionIDUploadingFile         -1441998364                     // .sendMessageUploadDocumentAction
#define kActionIDChoosingLocation      393186209                       // .sendMessageGeoLocationAction
#define kActionIDChoosingContact       1653390447                      // .sendMessageChooseContactAction
#define kActionIDPlayingGame           -580219064                      // .sendMessageGamePlayAction
#define kActionIDRecordingRoundVideo   -1997373508                     // .sendMessageRecordRoundAction
#define kActionIDUploadingRoundVideo   608050278                       // .sendMessageUploadRoundAction
#define kActionIDSpeakingInGroupCall   -651419003                      // .speakingInGroupCallAction
#define kActionIDReserverHistoryImport -606432698                      // .sendMessageHistoryImportAction
#define kActionIDChoosingSticker       -1336228175                     // .sendMessageChooseStickerAction
#define kActionIDEmojiInteraction      630664139                       // .sendMessageEmojiInteraction
#define kActionIDEmojiAcknowledgement -1234857938                      // .sendMessageEmojiInteractionSeen

#define kDisableOnlineStatus @"disableOnlineStatus"

#define kDisableTypingStatus @"disableTypingStatus"
#define kDisableRecordingVideoStatus @"disableRecordingVideoStatus"
#define kDisableUploadingVideoStatus @"disableUploadingVideoStatus"
#define kDisableRecordingVoiceStatus @"disableRecordingVoiceStatus"
#define kDisableUploadingVoiceStatus @"disableUploadingVoiceStatus"
#define kDisableUploadingPhotoStatus @"disableUploadingPhotoStatus"
#define kDisableUploadingFileStatus @"disableUploadingFileStatus"
#define kDisableChoosingLocationStatus @"disableChoosingLocationStatus"
#define kDisableChoosingContactStatus @"disableChoosingContactStatus"
#define kDisablePlayingGameStatus @"disablePlayingGameStatus"
#define kDisableRecordingRoundVideoStatus @"disableRecordingRoundVideoStatus"
#define kDisableUploadingRoundVideoStatus @"disableUploadingRoundVideoStatus"
#define kDisableSpeakingInGroupCallStatus @"disableSpeakingInGroupCallStatus"
#define kDisableChoosingStickerStatus @"disableChoosingStickerStatus"
#define kDisableEmojiInteractionStatus @"disableEmojiInteractionStatus"
#define kDisableEmojiAcknowledgementStatus @"disableEmojiAcknowledgementStatus"


#define kDisableMessageReadReceipt @"disableMessageReadReceipt"
#define kDisableStoriesReadReceipt @"disableStoriesReadReceipt"

#define kDisableAllAds @"TGExtraDisableAllAds"
#define kDisableForwardRestriction @"disableForwardRestriction"

// Privacy & Messages
#define kAntiRevoke @"TGExtraAntiRevoke"
#define kAntiSelfDestruct @"TGExtraAntiSelfDestruct"
#define kDisableScreenshotNotification @"TGExtraDisableScreenshotNotification"
#define kConfirmCalls @"TGExtraConfirmCalls"
#define kHideStories @"TGExtraHideStories"

#define FAKE_LOCATION_ENABLED_KEY @"TGExtraFakeLocation"
#define FAKE_LATITUDE_KEY @"TGExtraSavedLatitude"
#define FAKE_LONGITUDE_KEY @"TGExtraSavedLongitude"

#define FILE_PICKER_FIX_KEY @"TGExtraFixFilePicker"
#define FILE_PICKER_PATH @"TGExtraFileFixUsingSomeUglyHacks"
