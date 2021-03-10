from tkinter import *
from tkinter import font
from tkinter import messagebox
from PIL import Image, ImageTk
import frontend.register
import backend.dbconnection
import frontend.dashboard


class Login_Page:
    def __init__(self, root):
        self.root = root
        root.configure(bg='#074463')
        root.title('Login Page')
        root.geometry('900x600')
        root.resizable(0, 0)

        self.db = backend.dbconnection.DBConnect()
        f = font.Font(size=15, slant='italic', underline=TRUE, family='arial')

        lbl_header = Label(self.root, text='Login Page', font=('arial', 20, 'bold'), \
                           bg='silver', fg='black')
        lbl_header.pack(side=TOP, fill=X)

        main_frame = Frame(self.root, bg='silver', bd=5, relief=RAISED)
        main_frame.place(x=250, y=200, width=400, height=250)



        lbl_username = Label(main_frame, text='User Name:', font=('arial', 15, 'bold'), \
                             fg='Black', bg='silver')
        lbl_username.grid(row=0, column=0, padx=10, pady=10)

        self.ent_username = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_username.grid(row=0, column=1)
        self.ent_username.focus_set()

        lbl_password = Label(main_frame, text='Password:', font=('arial', 15, 'bold'), \
                             fg='Black', bg='silver')
        lbl_password.grid(row=1, column=0, padx=10, pady=10)

        self.ent_password = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_password.grid(row=1, column=1)

        btn_login = Button(main_frame, text='Login', font=('arial', 15, 'bold'), \
                           command=self.btn_login_click, bd=5, relief=RAISED)
        btn_login.place(x=150, y=120)

        btn_reset = Button(main_frame, text='Reset', font=('arial', 15, 'bold'), \
                           command=self.btn_reset_click, bd=5, relief=RAISED)
        btn_reset.place(x=250, y=120)

        lbl_signup = Label(main_frame, text='Create an account,Sign Up.', fg='red', bg='silver')
        lbl_signup['font'] = f
        lbl_signup.place(x=110, y=200)

        lbl_signup.bind('<Button-1>', self.lbl_signup_click)

    def btn_reset_click(self):
        self.ent_username.delete(0, END)
        self.ent_username.insert(0, "")

        self.ent_password.delete(0, END)
        self.ent_password.insert(0, '')

    def btn_login_click(self):
        uname = self.ent_username.get()
        passw = self.ent_password.get()
        print(passw)
        if self.ent_username.get() == '' or self.ent_password.get() == '':
            messagebox.showerror('Error', 'plz fill the empty field')
        else:
            query = "select * from new_table where Username=%s and Password=%s"
            values = (uname, passw)
            rows = self.db.select(query, values)
            data = []

            if len(rows) != 0:
                for row in rows:
                    data.append(row[0])
                    data.append(row[1])
                print(data)
                if uname == data[0] and passw == data[1]:
                    self.btn_reset_click()
                    messagebox.showinfo('Success', 'Congratulations!! login successful')
                    tk = Tk()
                    frontend.dashboard.Dashboard(tk)
                    self.root.destroy()

                else:
                    messagebox.showerror('Error', 'Invalid username and password')
            else:
                messagebox.showinfo("Error", "User not registered !! Register first")

    def lbl_signup_click(self, event):
        tk = Toplevel()
        frontend.register.Register_Page(tk)

