#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>

@interface TIRootListController : PSListController <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *editingKey;
@end
