// dark / mono input with a small lowercase label above. used by the
// admin-style settings forms where values are tokens (urls, regions,
// arn strings) and a monospaced face reads more accurately. for the
// brighter, theme-token style used in user-settings + signup, see the
// inline `Field` components there — different visual languages.

type Props = {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  disabled?: boolean;
};

export function MonoField({ label, value, onChange, placeholder, disabled }: Props) {
  return (
    <label className="block">
      <div className="text-xs text-neutral-400">{label}</div>
      <input
        type="text"
        value={value}
        placeholder={placeholder}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-md border border-neutral-800 bg-neutral-950 px-3 py-1.5 text-sm font-mono text-neutral-100 placeholder:text-neutral-700 focus:outline-none focus:ring-1 focus:ring-neutral-500"
      />
    </label>
  );
}
