import { useEffect, useState } from "react";

export function useOpenHours() {
  const [currentTime, setCurrentTime] = useState(new Date());
  const [isOpen, setIsOpen] = useState(false);
  const [isClosingSoon, setIsClosingSoon] = useState(false);
  const [timeRemaining, setTimeRemaining] = useState("");

  useEffect(() => {
    const timer = setInterval(() => {
      const now = new Date();
      setCurrentTime(now);
      const h = now.getHours();
      setIsOpen(h >= 8 && h < 20);
      setIsClosingSoon(h === 19);
      if (h === 19) {
        const target = new Date();
        target.setHours(20, 0, 0, 0);
        const diff = target.getTime() - now.getTime();
        const mins = Math.floor(diff / 60000);
        const secs = Math.floor((diff % 60000) / 1000);
        setTimeRemaining(`${mins}m ${secs}s`);
      } else {
        setTimeRemaining("");
      }
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  return { currentTime, isOpen, isClosingSoon, timeRemaining };
}
