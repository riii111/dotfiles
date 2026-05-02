{ ... }:

{
  system.defaults = {
    ".GlobalPreferences"."com.apple.mouse.scaling" = 2.0;

    NSGlobalDomain."com.apple.swipescrolldirection" = false;

    magicmouse.MouseButtonMode = "OneButton";

    CustomUserPreferences."com.apple.AppleMultitouchMouse" = {
      MouseHorizontalScroll = 1;
      MouseMomentumScroll = 1;
      MouseOneFingerDoubleTapGesture = 0;
      MouseTwoFingerDoubleTapGesture = 3;
      MouseTwoFingerHorizSwipeGesture = 2;
      MouseVerticalScroll = 1;
    };
  };
}
