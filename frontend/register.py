from tkinter import *
from tkinter import ttk

from tkinter import messagebox
import model.user
import backend.dbconnection


class Register_Page:
    def __init__(self, root):
        self.root = root
        root.configure(bg='#074463')
        self.root.title('Sign up')
        self.root.geometry('900x600')

        self.db = backend.dbconnection.DBConnect()

        lbl_heading = Label(self.root, text='Registration page', bg='silver', \
                            font=('arial', 20, 'bold'))
        lbl_heading.pack(side=TOP, fill=X)

        main_frame = Frame(self.root, bd=10, bg='silver')
        main_frame.place(x=250, y=180, width=400, height=350)

        lbl_uname = Label(main_frame, text='User Name', font=('arial', 15, 'bold'), \
                          bg='silver')
        lbl_uname.grid(row=0, column=0, padx=8, pady=10)

        self.ent_uname = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_uname.grid(row=0, column=1, padx=8, pady=10)

        lbl_password = Label(main_frame, text='Password', font=('arial', 15, 'bold'), \
                             bg='silver')
        lbl_password.grid(row=1, column=0, padx=8, pady=10)

        self.ent_password = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_password.grid(row=1, column=1, padx=8, pady=10)

        lbl_add = Label(main_frame, text='Address', font=('arial', 15, 'bold'), \
                        bg='silver')
        lbl_add.grid(row=2, column=0, padx=8, pady=10)

        self.ent_add = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_add.grid(row=2, column=1, padx=8, pady=10)

        lbl_college = Label(main_frame, text='college ID:', font=('arial', 15, 'bold'), \
                            bg='silver')
        lbl_college.grid(row=4, column=0, padx=8, pady=10)

        self.ent_college = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_college.grid(row=4, column=1, padx=8, pady=10)

        lbl_cmb = Label(main_frame, text='Gender', font=('arial', 15, 'bold'), \
                        background='silver')
        lbl_cmb.grid(row=3, column=0)

        self.cmb_gender = ttk.Combobox(main_frame, font=('arial', 15, 'bold'), state="readonly")
        self.cmb_gender['values'] = ('Male', 'Female', 'Others')
        self.cmb_gender.grid(row=3, column=1)

        btn_register = Button(self.root, text='Register', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE, \
                              command=self.add_click, padx=5)
        btn_register.place(x=250, y=550)

        btn_reset = Button(self.root, text='Reset', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                           command=self.reset_click, padx=5)
        btn_reset.place(x=380, y=550)

    def reset_click(self):
        self.ent_uname.delete(0, END)
        self.ent_uname.insert(0, "")
        self.ent_password.delete(0, END)
        self.ent_password.insert(0, '')
        self.ent_add.delete(0, END)
        self.ent_add.insert(0, '')
        self.ent_college.delete(0, END)
        self.ent_college.insert(0, '')

    def add_click(self):
        username = self.ent_uname.get()
        password = self.ent_password.get()
        add = self.ent_add.get()
        gender = self.cmb_gender.get()
        college = self.ent_college.get()

        if username == '' or password == '' or add == '' or gender == '' or college == '':
            messagebox.showerror('Error', 'plz fill the empty field')
            return

        u = model.user.User(username, password, add, gender, college)

        query = "insert into new_table(Username,Password,Address,Gender,college) values(%s,%s,%s,%s,%s)"
        values = (u.get_username(), u.get_password(), u.get_address(), u.get_gender(), u.get_college())

        self.db.insert(query, values)
        messagebox.showinfo('Success', 'User Registration successfull')
        self.root.destroy()
