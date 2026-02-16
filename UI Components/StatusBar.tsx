"use client";

interface StatusBarProps {
  isOpen: boolean;
  isClosingSoon: boolean;
  timeRemaining: string;
}

export default function StatusBar({ isOpen, isClosingSoon, timeRemaining }: StatusBarProps) {
  return (
    <div
      className={`flex items-center gap-4 py-3 px-4 rounded-lg border transition-all duration-500 ${
        !isOpen
          ? "bg-red-500/5 border-red-500/20"
          : isClosingSoon
            ? "bg-yellow-500/10 border-yellow-500/40 shadow-[0_0_20px_rgba(234,179,8,0.2)]"
            : "bg-green-500/5 border-green-500/20"
      }`}
    >
      <div
        className={`w-2.5 h-2.5 rounded-full ${
          !isOpen ? "bg-red-500" : isClosingSoon ? "bg-yellow-500 animate-bounce" : "bg-green-500 animate-pulse"
        }`}
      />

      <div className="flex flex-col">
        <p
          className={`text-[10px] font-black uppercase tracking-[0.2em] ${
            !isOpen ? "text-red-400" : isClosingSoon ? "text-yellow-500" : "text-green-400"
          }`}
        >
          {!isOpen ? "Entries Closed" : isClosingSoon ? "Closing Soon" : "Entries Open"}
        </p>
        <p className="text-xs text-slate-400 font-medium">{isOpen ? "Closes at 8:00 PM" : "Opens at 8:00 AM"}</p>
      </div>

      {/* Dynamic Countdown / Draw Time */}
      <div className="ml-auto text-right">
        {isClosingSoon ? (
          <div className="flex flex-col animate-in fade-in slide-in-from-right-2">
            <span className="text-yellow-500/70 text-[9px] block uppercase font-black tracking-tighter">
              Time Remaining
            </span>
            <span className="text-yellow-500 font-mono font-black text-lg drop-shadow-[0_0_8px_rgba(234,179,8,0.5)]">
              {timeRemaining}
            </span>
          </div>
        ) : (
          <div className="flex flex-col">
            <span className="text-slate-500 text-[9px] block uppercase font-bold">Next Grand Draw</span>
            <span className="text-white font-black text-sm uppercase">9:00 PM Local</span>
          </div>
        )}
      </div>
    </div>
  );
}
