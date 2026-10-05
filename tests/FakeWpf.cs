#pragma warning disable 67
using System; using System.Collections.ObjectModel;
namespace System.Windows { public static class SystemParameters { public static bool ClientAreaAnimation = false; }
  public struct Point { public Point(double x,double y){} }
  public enum FlowDirection { LeftToRight }
  public static class FontStyles { public static object Normal = 1; }
  public static class FontWeights { public static object Bold = 1; }
  public static class FontStretches { public static object Normal = 1; }
  public class Thickness { public Thickness(double a){} } }
namespace Windows.Controls {
  public class ElCollection : Collection<object> {
    public object Owner; public ElCollection(object o){ Owner=o; }
    public bool Loose; protected override void InsertItem(int i, object item){ var e=item as FE; if(e!=null && !Loose){ if(e.Parent!=null) throw new InvalidOperationException("Element already has a logical parent: "+e.GetType().Name); e.Parent=Owner;} base.InsertItem(i,item); }
    protected override void RemoveItem(int i){ var e=this[i] as FE; if(e!=null) e.Parent=null; base.RemoveItem(i); }
    protected override void ClearItems(){ foreach(var x in this){ var e=x as FE; if(e!=null) e.Parent=null; } base.ClearItems(); }
  }
  public class FE {
    public object Parent; public string Text; public double FontSize; public object FontWeight, TextWrapping, Margin, Padding, VerticalAlignment, HorizontalAlignment, Foreground, Background, Style, Tag, Content, Orientation, Cursor, ToolTip, Visibility, Fill, Effect, BorderBrush, FontFamily, CornerRadius, BorderThickness, TextTrimming;
    object _child; public object Child { get { return _child; } set { var e=value as FE; if(e!=null){ if(e.Parent!=null) throw new InvalidOperationException("Child already has a parent"); e.Parent=this; } _child=value; } }
    public bool ClipToBounds; public double Width, Height, Opacity = 1, Value, StrokeThickness; public object Stroke, StrokeLineJoin, Data, StrokeStartLineCap, StrokeEndLineCap, Stretch; public string Title; public bool? IsChecked; public string GroupName; public bool IsEnabled = true;
    public ElCollection Children, Items; public Collection<object> RowDefinitions = new Collection<object>(), ColumnDefinitions = new Collection<object>();
    public FE(){ Children = new ElCollection(this); Items = new ElCollection(this); }
    public void SetResourceReference(object dp, object key){ if(key==null) throw new ArgumentNullException("key"); }
    public object SetBinding(object dp, object b){ return null; }
    public void ScrollIntoView(object o){}
    public event EventHandler Click, Checked, MouseLeftButtonUp, ValueChanged, TextChanged, KeyDown, MouseEnter, MouseLeave, MouseLeftButtonDown, PreviewKeyDown;
    public bool HasHandler(string n){ var f = typeof(FE).GetField(n, System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance); return f != null && f.GetValue(this) != null; }
    public void Raise(string n){ var f = typeof(FE).GetField(n, System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance); var d = f.GetValue(this) as Delegate; if (d != null) d.DynamicInvoke(this, EventArgs.Empty); }
  }
  public class StackPanel : FE {} public class WrapPanel : FE {} public class Grid : FE { public static void SetColumn(object e,int c){} public static void SetRow(object e,int r){} }
  public class ColumnDefinition { public object Width; } public class RowDefinition { public object Height; }
  public class CheckBox : FE {} public class RadioButton : FE {} public class Button : FE {} public class Border : FE {} public class ListBox : FE {} public class TextBox : FE {}
  public class TextBlock : FE { public static object ForegroundProperty = "Foreground"; }
  public class Control : FE { public static object BackgroundProperty = "Background"; public static object BorderBrushProperty = "BorderBrush"; public static object ForegroundProperty = "Foreground"; }
}
namespace Windows.Media {
  public struct Color { public byte R,G,B,A; public static Color FromRgb(byte r, byte g, byte b){ return new Color{R=r,G=g,B=b,A=255}; } }
  public static class ColorConverter { public static object ConvertFromString(string s){ s=s.TrimStart('#'); return Color.FromRgb(Convert.ToByte(s.Substring(0,2),16),Convert.ToByte(s.Substring(2,2),16),Convert.ToByte(s.Substring(4,2),16)); } }
  public class SolidColorBrush { public double Opacity = 1; public SolidColorBrush(Color c){} public void Freeze(){} }
  public class LinearGradientBrush { public LinearGradientBrush(Color a, Color b, double ang){} }
  public class FontFamily { public FontFamily(string s){} }
  public static class Geometry { public static object Parse(string s){ if (string.IsNullOrEmpty(s)) throw new FormatException("empty geometry"); return new object(); } }
  public class Typeface { public Typeface(FontFamily f, object s, object w, object st){} }
  public class FormattedText { public double WidthIncludingTrailingWhitespace = 30, Height = 60; public FormattedText(string t, System.Globalization.CultureInfo c, System.Windows.FlowDirection d, Typeface tf, double size, object brush){} public FakeGeometry BuildGeometry(System.Windows.Point p){ return new FakeGeometry(); } }
  public class FakeGeometry { public FakeRect Bounds = new FakeRect(); }
  public class FakeRect { public double Right = 34, Bottom = 71; }
}
namespace Windows.Media.Effects { public class DropShadowEffect { public Windows.Media.Color Color; public double BlurRadius, ShadowDepth, Opacity; } }
namespace Windows.Shapes { public class Ellipse : Windows.Controls.FE {} public class Path : Windows.Controls.FE {} }
namespace Windows.Data { public enum RelativeSourceMode { FindAncestor } public class RelativeSource { public RelativeSource(RelativeSourceMode m, Type t, int l){} } public class Binding { public object RelativeSource; public Binding(string p){} } }
