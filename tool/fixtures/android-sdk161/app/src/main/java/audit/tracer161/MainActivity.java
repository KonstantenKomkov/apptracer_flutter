package audit.tracer161;

public final class MainActivity extends android.app.Activity {
    @Override public void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        android.widget.Button button = new android.widget.Button(this);
        button.setText(getPackageName());
        button.setOnClickListener(view -> VariantCrash.trigger());
        setContentView(button);
    }
}
